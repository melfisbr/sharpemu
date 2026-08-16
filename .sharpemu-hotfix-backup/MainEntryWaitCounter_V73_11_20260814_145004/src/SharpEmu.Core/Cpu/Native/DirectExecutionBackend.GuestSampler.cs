// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;

namespace SharpEmu.Core.Cpu.Native;

/// <summary>
/// Sampling profiler for guest code. Managed profilers only see the emulator's
/// own frames — once a guest thread is running translated code it is opaque to
/// them, so a title that burns its cores inside its own spin loops looks like
/// unattributed native time. This walks the guest thread registry and samples
/// each thread's host RIP, which lands directly on the guest instruction being
/// executed.
/// </summary>
public sealed partial class DirectExecutionBackend
{
	private static readonly bool _profileGuestRip =
		string.Equals(
			Environment.GetEnvironmentVariable("SHARPEMU_PROFILE_GUEST_RIP"),
			"1",
			StringComparison.Ordinal);

	private static readonly int _profileGuestRipIntervalMs =
		int.TryParse(
			Environment.GetEnvironmentVariable("SHARPEMU_PROFILE_GUEST_RIP_INTERVAL_MS"),
			out var interval) && interval > 0
			? interval
			: 2;

	private static readonly int _profileGuestRipReportSeconds =
		int.TryParse(
			Environment.GetEnvironmentVariable("SHARPEMU_PROFILE_GUEST_RIP_REPORT_S"),
			out var report) && report > 0
			? report
			: 15;

	private const ulong GuestImageBase = 0x0000_0008_0000_0000UL;
	private const ulong GuestImageLimit = 0x0000_0009_0000_0000UL;

	private int _guestRipSamplerStarted;
	private readonly ConcurrentDictionary<ulong, long> _guestRipSamples = new();
	private readonly ConcurrentDictionary<string, long> _guestRipThreadSamples = new();
	private readonly ConcurrentDictionary<string, long> _guestWaitSamples = new();
	private readonly ConcurrentDictionary<string, long> _guestThreadWaitSamples = new();
	private long _guestRipTotalSamples;
	private long _guestWaitTotalSamples;
	private long _guestRipCaptureFailures;
	private long _guestRipSamplerErrors;
	private int _guestRipSampleCursor;

	// V73.9: exact Demon's Souls UI native-method reachability, derived from
	// audited EBOOT EH-frame function ranges + RIP-relative string xrefs.
	// Dormant unless SHARPEMU_TRACE_DEMONS_UI_METHODS=1.
	private static readonly bool _traceDemonsUiMethodsV739 =
		string.Equals(
			Environment.GetEnvironmentVariable("SHARPEMU_TRACE_DEMONS_UI_METHODS"),
			"1",
			StringComparison.Ordinal);

	private readonly record struct DemonsUiMethodRangeV739(
		ulong Start,
		ulong End,
		string Name);

	private static readonly DemonsUiMethodRangeV739[] _demonsUiMethodRangesV739 =
	[
		new(0x00DC2500UL, 0x00DC2580UL, "HasOpenMenus"),
		new(0x00DC4DE0UL, 0x00DC5750UL, "PrintSceneState"),
		new(0x00DCF210UL, 0x00DD0C80UL, "ShowHudSceneRegion"),
		new(0x00DDAD30UL, 0x00DDAEB0UL, "TransitionShowHUDValidate"),
		new(0x01488C20UL, 0x01488C30UL, "ShowLegacyMenuA"),
		new(0x014893F0UL, 0x01489410UL, "ShowLegacyMenuB"),
		new(0x0148ED10UL, 0x0148F350UL, "StartMenuThink"),
		new(0x0148F350UL, 0x0148F8C0UL, "StartMenuHandleInputFocus"),
	];

	private readonly ConcurrentDictionary<string, long> _demonsUiMethodSamplesV739 = new();
	private readonly ConcurrentDictionary<string, byte> _demonsUiMethodFirstHitsV739 = new();

	/// <summary>
	/// Names the HLE call a thread is parked in, using the guest RIP the import
	/// dispatcher left on its context.
	/// </summary>

	private void RecordDemonsUiMethodRipV739(
		ulong hostRip,
		GuestThreadState thread)
	{
		if (!_traceDemonsUiMethodsV739 ||
			hostRip < GuestImageBase ||
			hostRip >= GuestImageLimit)
		{
			return;
		}

		var appRip = hostRip - GuestImageBase;
		foreach (var range in _demonsUiMethodRangesV739)
		{
			if (appRip < range.Start || appRip >= range.End)
			{
				continue;
			}

			var count = _demonsUiMethodSamplesV739.AddOrUpdate(
				range.Name,
				1,
				static (_, value) => value + 1);

			if (_demonsUiMethodFirstHitsV739.TryAdd(range.Name, 1))
			{
				Console.Error.WriteLine(
					$"[V73.9][UI_RIP] first_hit name={range.Name} " +
					$"app=0x{appRip:X} host=0x{hostRip:X} " +
					$"thread={(string.IsNullOrEmpty(thread.Name) ? "<unnamed>" : thread.Name)} " +
					$"samples={count}");
			}

			return;
		}
	}

	private void ReportDemonsUiMethodSamplesV739()
	{
		if (!_traceDemonsUiMethodsV739)
		{
			return;
		}

		Console.Error.WriteLine(
			"[V73.9][UI_RIP] counts " +
			string.Join(
				" ",
				_demonsUiMethodRangesV739.Select(range =>
					$"{range.Name}=" +
					(_demonsUiMethodSamplesV739.TryGetValue(range.Name, out var count)
						? count
						: 0))));
	}

	private string ResolveWaitLabel(GuestThreadState thread)
	{
		var context = thread.Context;
		if (context is null)
		{
			return "<no-context>";
		}

		var importIndex = context.ActiveImportIndex;
		if ((uint)importIndex >= (uint)_importEntries.Length)
		{
			// Host code with no import in flight: the thread is parked by the
			// emulator's own scheduler. The cooperative block records why, which
			// is the part that actually identifies what the frame is waiting on.
			var blockReason = thread.BlockReason;
			return string.IsNullOrEmpty(blockReason)
				? "<idle-or-scheduler>"
				: $"blocked:{blockReason}";
		}

		var entry = _importEntries[importIndex];
		return entry.Export?.Name ?? entry.Nid;
	}

	internal void ClearActiveImportIndex()
	{
		if (!_profileGuestRip)
		{
			return;
		}

		var context = ActiveCpuContext;
		if (context is not null)
		{
			context.ActiveImportIndex = -1;
		}
	}

	private void EnsureGuestRipSampler()
	{
		if (!_profileGuestRip ||
			!OperatingSystem.IsWindows() ||
			Interlocked.Exchange(ref _guestRipSamplerStarted, 1) != 0)
		{
			return;
		}

		var sampler = new Thread(GuestRipSampleLoop)
		{
			IsBackground = true,
			Name = "SharpEmu guest RIP sampler",
			// Sampling suspends guest threads briefly. Keep this diagnostic below
			// the title workers so it observes them without becoming the bottleneck.
			Priority = ThreadPriority.BelowNormal,
		};
		sampler.Start();
		Console.Error.WriteLine(
			$"[PERF][GUEST] RIP sampler started: interval={_profileGuestRipIntervalMs}ms " +
			$"report={_profileGuestRipReportSeconds}s");
	}

	private void GuestRipSampleLoop()
	{
		var clock = Stopwatch.StartNew();
		var lastReportMs = 0L;
		var lastReportSamples = 0L;

		while (true)
		{
			try
			{
				var guestThreads = SnapshotGuestThreads();
				var sampleIndex = guestThreads.Length == 0
					? 0
					: (int)((uint)Interlocked.Increment(ref _guestRipSampleCursor) % (uint)guestThreads.Length);
				foreach (var thread in guestThreads.Skip(sampleIndex).Take(1))
				{
					var hostThreadId = Volatile.Read(ref thread.HostThreadId);
					if (hostThreadId == 0)
					{
						continue;
					}

					if (!TryCaptureHostThreadContext(hostThreadId, out var snapshot) ||
						!snapshot.IsValid)
					{
						Interlocked.Increment(ref _guestRipCaptureFailures);
						continue;
					}

					_guestRipSamples.AddOrUpdate(snapshot.Rip, 1, static (_, value) => value + 1);
					_guestRipThreadSamples.AddOrUpdate(
						string.IsNullOrEmpty(thread.Name) ? "<unnamed>" : thread.Name,
						1,
						static (_, value) => value + 1);
					Interlocked.Increment(ref _guestRipTotalSamples);

					// A host RIP means the thread is inside the emulator rather
					// than running translated code. DispatchImport parks the
					// guest RIP on the import stub for the call being serviced,
					// so the stub address names what the thread is waiting on —
					// no hot-path bookkeeping needed to find out.
					if (snapshot.Rip >= GuestImageBase && snapshot.Rip < GuestImageLimit)
					{
						RecordDemonsUiMethodRipV739(snapshot.Rip, thread);
						continue;
					}

					_guestWaitSamples.AddOrUpdate(
						ResolveWaitLabel(thread),
						1,
						static (_, value) => value + 1);
					_guestThreadWaitSamples.AddOrUpdate(
						string.IsNullOrEmpty(thread.Name) ? "<unnamed>" : thread.Name,
						1,
						static (_, value) => value + 1);
					Interlocked.Increment(ref _guestWaitTotalSamples);
				}

				Thread.Sleep(_profileGuestRipIntervalMs);

				var elapsedMs = clock.ElapsedMilliseconds;
				if (elapsedMs - lastReportMs < _profileGuestRipReportSeconds * 1000L)
				{
					continue;
				}

				var samples = Interlocked.Read(ref _guestRipTotalSamples);
				ReportGuestRipSamples(samples - lastReportSamples, (elapsedMs - lastReportMs) / 1000.0);
				lastReportMs = elapsedMs;
				lastReportSamples = samples;
			}
			catch (Exception exception)
			{
				// A title can tear down a thread or its context during a capture.
				// The profiler must never silently die or affect guest execution.
				if (Interlocked.Increment(ref _guestRipSamplerErrors) == 1)
				{
					Console.Error.WriteLine($"[PERF][GUEST] sampler recovery: {exception.GetType().Name}: {exception.Message}");
				}
			}
		}
	}

	private void ReportGuestRipSamples(long windowSamples, double windowSeconds)
	{
		var total = Interlocked.Read(ref _guestRipTotalSamples);
		if (total == 0)
		{
			return;
		}

		var byRip = new List<KeyValuePair<ulong, long>>(_guestRipSamples.Count + 16);
		foreach (var pair in _guestRipSamples)
		{
			byRip.Add(pair);
		}

		// A tight spin lands on a handful of instructions; grouping by 4 KB page
		// as well shows which routine those instructions belong to.
		var byPage = new Dictionary<ulong, long>();
		foreach (var pair in byRip)
		{
			var page = pair.Key & ~0xFFFUL;
			byPage[page] = byPage.TryGetValue(page, out var existing)
				? existing + pair.Value
				: pair.Value;
		}

		var byThread = new List<KeyValuePair<string, long>>(_guestRipThreadSamples.Count + 16);
		foreach (var pair in _guestRipThreadSamples)
		{
			byThread.Add(pair);
		}

		Console.Error.WriteLine(
			$"[PERF][GUEST] samples={total} window={windowSamples} in {windowSeconds:F1}s " +
			$"capture_failures={Interlocked.Read(ref _guestRipCaptureFailures)}");

		Console.Error.WriteLine(
			"[PERF][GUEST] top_rip: " +
			string.Join(
				" | ",
				byRip.OrderByDescending(pair => pair.Value)
					.Take(12)
					.Select(pair =>
						$"0x{pair.Key:X}{DescribeGuestAddress(pair.Key)}={pair.Value * 100.0 / total:F1}%")));

		Console.Error.WriteLine(
			"[PERF][GUEST] top_page: " +
			string.Join(
				" | ",
				byPage.OrderByDescending(pair => pair.Value)
					.Take(8)
					.Select(pair =>
						$"0x{pair.Key:X}{DescribeGuestAddress(pair.Key)}={pair.Value * 100.0 / total:F1}%")));

		var byWait = new List<KeyValuePair<string, long>>(_guestWaitSamples.Count + 16);
		foreach (var pair in _guestWaitSamples)
		{
			byWait.Add(pair);
		}

		var waitTotal = Interlocked.Read(ref _guestWaitTotalSamples);
		Console.Error.WriteLine(
			$"[PERF][GUEST] waiting={waitTotal * 100.0 / total:F1}% of guest thread-time; top_wait: " +
			string.Join(
				" | ",
				byWait.OrderByDescending(pair => pair.Value)
					.Take(12)
					.Select(pair => $"{pair.Key}={pair.Value * 100.0 / total:F1}%")));

		// Per-thread spin/park split. The global wait share mixes the job pool in
		// with a dozen dormant threads, which hides the number that matters:
		// how much of a core each worker actually burns.
		ReportDemonsUiMethodSamplesV739();

		Console.Error.WriteLine(
			"[PERF][GUEST] thread_split (running/parked): " +
			string.Join(
				" | ",
				byThread.OrderByDescending(pair => pair.Value)
					.Take(10)
					.Select(pair =>
					{
						var parked = _guestThreadWaitSamples.TryGetValue(pair.Key, out var wait) ? wait : 0;
						var running = pair.Value - parked;
						return $"{pair.Key}={running * 100.0 / pair.Value:F0}%/{parked * 100.0 / pair.Value:F0}%";
					})));

		Console.Error.WriteLine(
			"[PERF][GUEST] top_thread: " +
			string.Join(
				" | ",
				byThread.OrderByDescending(pair => pair.Value)
					.Take(10)
					.Select(pair => $"{pair.Key}={pair.Value * 100.0 / total:F1}%")));
	}

	/// <summary>
	/// Tags a sampled address with the region it belongs to. Guest module code
	/// lives above the image base; anything else is emulator or system code that
	/// the managed profiler already covers.
	/// </summary>
	private string DescribeGuestAddress(ulong address)
	{
		
		

		if (address >= GuestImageBase && address < GuestImageLimit)
		{
			return $"(app+0x{address - GuestImageBase:X})";
		}

		for (var index = 0; index < _importEntries.Length; index++)
		{
			if (_importEntries[index].Address == (address & ~0xFUL))
			{
				return $"(stub:{_importEntries[index].Nid})";
			}
		}

		return "(host)";
	}
}
