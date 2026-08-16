SharpEmu attract_movie.bk2 direct test V70.4.3.0.3

Observed V70.4.3.0.2 failure:
  $psi.ArgumentList.Add($dll)
  -> "Não é possível chamar um método em uma expressão de valor nulo."

Root cause:
Windows PowerShell 5.1 uses the .NET Framework ProcessStartInfo implementation,
where the modern ArgumentList collection is unavailable/not usable.

V70.4.3.0.3 uses the legacy ProcessStartInfo.Arguments string with explicit
native argument quoting. This is compatible with Windows PowerShell 5.1.

Run from the SharpEmu repository root:
  .\RUN_ATTRACT_MOVIE_DIRECT_V70_4_3_0_3.cmd
