using System;
using System.Reflection;

var dll = args[0];
var nid = args[1];

var assembly = Assembly.LoadFrom(dll);
var type = assembly.GetType("SharpEmu.HLE.Aerolib")
    ?? throw new Exception("Aerolib não encontrado.");

var instance = type.GetProperty(
    "Instance",
    BindingFlags.Public | BindingFlags.Static
)!.GetValue(null)!;

var method = type.GetMethod("GetName")
    ?? throw new Exception("GetName não encontrado.");

Console.WriteLine(method.Invoke(instance, new object[] { nid }));
