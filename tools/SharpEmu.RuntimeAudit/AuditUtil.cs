using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace SharpEmu.RuntimeAudit;

internal static class AuditUtil
{
    public static string Sha256File(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    public static string Csv(string? value)
    {
        value ??= "";
        if (!value.Contains(',') && !value.Contains('"') && !value.Contains('\r') && !value.Contains('\n'))
            return value;
        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }

    public static string RelativeOrFull(string root, string path)
    {
        try { return Path.GetRelativePath(root, path); }
        catch { return path; }
    }

    public static async Task<string> RunCaptureAsync(
        string fileName,
        string arguments,
        string workingDirectory,
        int timeoutMs = 15000)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process is null)
                return "";

            using var cts = new CancellationTokenSource(timeoutMs);
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cts.Token);
            var stderrTask = process.StandardError.ReadToEndAsync(cts.Token);
            await process.WaitForExitAsync(cts.Token);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            return (stdout + Environment.NewLine + stderr).Trim();
        }
        catch
        {
            return "";
        }
    }

    public static double ParseDouble(string raw)
    {
        if (double.TryParse(
                raw.Replace(',', '.'),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var value))
            return value;
        return 0;
    }

    public static long ParseLong(string raw)
    {
        return long.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value
            : 0;
    }

    public static string FormatBytes(long bytes)
    {
        string[] suffix = ["B", "KB", "MB", "GB", "TB"];
        double value = Math.Max(0, bytes);
        var index = 0;
        while (value >= 1024 && index < suffix.Length - 1)
        {
            value /= 1024;
            index++;
        }
        return $"{value:F2} {suffix[index]}";
    }

    public static bool IsExcludedRepoPath(string path)
    {
        var normalized = path.Replace('\\', '/');
        string[] excluded =
        [
            "/.git/", "/bin/", "/obj/", "/artifacts/", "/Backup/",
            "/.sharpemu-hotfix-backup/", "/.sharpemu-v38-backup/",
            "/SharpEmu_RuntimeAudit_Result_", "/node_modules/"
        ];
        return excluded.Any(x => normalized.Contains(x, StringComparison.OrdinalIgnoreCase));
    }

    public static string SanitizeFileName(string value)
    {
        foreach (var c in Path.GetInvalidFileNameChars())
            value = value.Replace(c, '_');
        return value;
    }
}
