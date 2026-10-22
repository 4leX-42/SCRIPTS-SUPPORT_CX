using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace InstaladorImpresoras
{
    enum ScanState { Pending, Checking, Printer, NotPrinter, Unreachable }

    sealed class ScanResult
    {
        public ScanState State;
        public string Model = "";         // texto corto para la lista: modelo o motivo ("offline", "sin permiso")
        public string Hint = "";          // explicacion larga para el detalle cuando no se detecta
        public string Description = "";   // todo lo que dice el equipo (SNMP / IPP / web / driver de la cola)
        public string Brand = "";         // "Ricoh", "Canon", "Servidor" o vacio
        public string Name = "", Location = "";   // tal cual en la impresora (SNMP) o en la cola del servidor
        public List<int> Ports = new List<int>();
        public long? PingMs;
        /// <summary>"Procesal Dcha · Planta 3"; vacio si la impresora solo tiene el nombre de fabrica.</summary>
        public string Friendly => NetworkScan.Friendly(Name, Location, Model);
    }

    /// <summary>Una fila del escaner: impresora del directorio o encontrada al escanear un rango.</summary>
    sealed class ScanEntry
    {
        public string Ip, Group;
        public OfficePrinter Directory;   // null = no esta en oficinas.txt
        public ScanState State = ScanState.Pending;
        public ScanResult Result;
        public bool Detected => State == ScanState.Printer;
        public bool Failed => State == ScanState.Unreachable || State == ScanState.NotPrinter;
        public bool IsShared => Ip.StartsWith(@"\\");
        public string Brand => Result != null && Result.Brand.Length > 0 ? Result.Brand : Directory?.Brand ?? "";
        public string Friendly => Result?.Friendly ?? "";
        public string Label => Directory != null ? Directory.Label : Friendly.Length > 0 ? Friendly : "Sin nombre";
        public bool CanInstall => Detected && (Brand == "Ricoh" || Brand == "Canon" || IsShared);
        /// <summary>
        /// Nombre de cola al instalar: el del directorio; si no, "Marca - nombre y planta de la impresora"
        /// (como "Canon - Cultura"); si la impresora no tiene nombre, "Ricoh IM C4500" / "Ricoh 192.168.1.50".
        /// </summary>
        public string QueueName
        {
            get
            {
                if (Directory != null && (Directory.Location.Length > 0 || Directory.Brand.Length > 0)) return Cut(Directory.QueueName);
                if (Friendly.Length > 0) return Cut($"{(Brand.Length > 0 ? Brand : "Impresora")} - {Friendly}");
                var m = RicohModels.Detect(Result?.Description ?? "");
                return Cut(m != null ? "Ricoh " + m.Display : $"{(Brand.Length > 0 ? Brand : "Impresora")} {Ip}");
            }
        }
        static string Cut(string s) => s.Length > 60 ? s.Substring(0, 60) : s;
    }

    /// <summary>
    /// Escaner de impresoras. Por IP: ping + puertos de impresion (9100 RAW, 631 IPP, 515 LPD) y, si hay
    /// alguno, identificacion en cascada: SNMP (modelo, nombre y ubicacion en una consulta) -> IPP -> web.
    /// Colas compartidas: puerto 445 (SMB) del servidor y apertura real de la cola con winspool.
    /// </summary>
    static class NetworkScan
    {
        static readonly int[] Ports = { 9100, 631, 515, 80 };
        static readonly Regex PrinterWords = new Regex(@"printer|print server|ricoh|savin|lanier|gestetner|nashuatec|canon|imagerunner|imageforce|i-sensys|laserjet|officejet|jetdirect|brother|epson|kyocera|ecosys|taskalfa|xerox|lexmark|konica|bizhub|sharp|toshiba|e-studio|\boki\b|samsung", RegexOptions.IgnoreCase);
        static readonly Regex RicohWords = new Regex("ricoh|savin|lanier|gestetner|nashuatec|nrg|rex-rotary|infotec", RegexOptions.IgnoreCase);
        static readonly Regex CanonWords = new Regex(@"canon|imagerunner|imageforce|i-sensys|\bimageclass\b", RegexOptions.IgnoreCase);

        /// <summary>
        /// Comprueba una IP. quick = pasada de rango: timeouts cortos y solo identifica si hay puerto de impresion.
        /// </summary>
        public static async Task<ScanResult> Check(string ip, bool quick, CancellationToken ct)
        {
            var r = new ScanResult();
            int timeout = quick ? 450 : 1000;
            var ping = PingAsync(ip, timeout);
            var open = Ports.Select(p => TcpOpenAsync(ip, p, timeout)).ToArray();
            await Task.WhenAll(open).ConfigureAwait(false);
            r.PingMs = await ping.ConfigureAwait(false);
            for (int i = 0; i < Ports.Length; i++) if (open[i].Result) r.Ports.Add(Ports[i]);
            // 9100 / 631 = impresora; 515 (LPD) tambien lo abren los servidores Windows, solo cuenta si se identifica
            bool printPort = r.Ports.Contains(9100) || r.Ports.Contains(631);
            bool anyPrintPort = printPort || r.Ports.Contains(515);
            bool alive = r.PingMs != null || r.Ports.Count > 0;
            // sin ping ni puertos no se pregunta nada mas: SNMP solo esperaria a que venza el tiempo
            if (!alive || (quick && !anyPrintPort)) return Fail(r, alive);
            ct.ThrowIfCancellationRequested();

            string snmp = null, snmpModel = null, ipp = null, web = null;
            await Task.Run(() =>
            {
                var info = PrinterProbe.SnmpInfo(ip, quick ? 800 : 1500, quick ? 1 : 2);
                if (info != null) { snmp = info.Value.descr; snmpModel = info.Value.model; r.Name = info.Value.name; r.Location = info.Value.location; }
                // IPP y web solo si SNMP no basta para saber que es
                if (!PrinterWords.IsMatch(snmp ?? "") && r.Ports.Contains(631)) ipp = PrinterProbe.IppMakeAndModel(ip);
                if (ipp == null && !PrinterWords.IsMatch(snmp ?? "") && r.Ports.Contains(80) && (printPort || !quick)) web = PrinterProbe.HttpDescription(ip);
            }, ct).ConfigureAwait(false);

            r.Description = string.Join(" | ", new[] { snmp, ipp, web }.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()).Distinct());
            if (!printPort && !PrinterWords.IsMatch(r.Description)) return Fail(r, alive || r.Description.Length > 0);

            r.Model = CleanModel(ipp ?? snmpModel ?? web ?? "");
            r.Brand = RicohWords.IsMatch(r.Description) ? "Ricoh" : CanonWords.IsMatch(r.Description) ? "Canon" : "";
            r.State = ScanState.Printer;
            return r;
        }

        /// <summary>"RICOH IM C4500 9.00.1 / RICOH Network Printer C model" -> "RICOH IM C4500".</summary>
        static string CleanModel(string m)
        {
            m = m.Split(new[] { " / ", ",", ";", " | " }, StringSplitOptions.None)[0];
            m = Regex.Replace(m, @"\s\d+(\.\d+){1,3}\b", "");   // versiones de firmware
            m = Regex.Replace(m, @"\s+", " ").Trim();
            return m.Length > 48 ? m.Substring(0, 48) + "…" : m;
        }

        static ScanResult Fail(ScanResult r, bool alive)
        {
            r.State = alive ? ScanState.NotPrinter : ScanState.Unreachable;
            r.Model = alive ? "host · sin servicio de impresión" : "offline";
            r.Hint = alive ? "El equipo responde pero no ofrece impresión (9100 / 631 / 515)."
                           : "Sin respuesta: apagada, IP cambiada o sin ruta hasta esa red.";
            return r;
        }

        /// <summary>
        /// Cola compartida (\\servidor\cola): ping al servidor, puerto 445 (SMB) y apertura real de la cola
        /// con winspool, que devuelve su driver, estado, ubicacion y comentario.
        /// </summary>
        public static async Task<ScanResult> CheckShared(string unc)
        {
            var r = new ScanResult { Brand = "Servidor" };
            var host = unc.TrimStart('\\').Split('\\')[0];
            var ping = PingAsync(host, 1000);
            // incluye resolver el nombre; un reintento porque algunos servidores frenan conexiones seguidas
            bool smb = await TcpOpenAsync(host, 445, 3000).ConfigureAwait(false) || await TcpOpenAsync(host, 445, 3000).ConfigureAwait(false);
            r.PingMs = await ping.ConfigureAwait(false);
            if (!smb)
            {
                r.State = ScanState.Unreachable;
                r.Model = r.PingMs != null ? "SMB cerrado" : "servidor offline";
                r.Hint = r.PingMs != null ? $"{host} responde pero no comparte (puerto 445 cerrado)." : $"{host} no responde.";
                return r;
            }
            r.Ports.Add(445);
            int error = 0;
            var info = await Task.Run(() => SharedQueueInfo(unc, out error)).ConfigureAwait(false);
            if (info == null)
            {
                r.State = ScanState.NotPrinter;
                bool denied = error == 5 || error == 1326;
                r.Model = denied ? $"sin permiso · {error}" : error == 1801 ? "cola inexistente" : $"error {error}";
                r.Hint = denied ? $"{host} no acepta este usuario: inicie sesión con un usuario del dominio."
                       : error == 1801 ? $"No existe esa cola en {host}: revise el nombre."
                       : $"No se pudo abrir la cola en {host} (error {error}).";
                return r;
            }
            r.State = ScanState.Printer;
            r.Description = r.Model = info.Value.driver;
            r.Name = info.Value.comment;
            r.Location = info.Value.location;
            if (info.Value.status != 0) r.Hint = "El servidor marca la cola con error o sin conexión.";
            return r;
        }

        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
        [DllImport("winspool.drv", SetLastError = true)] static extern bool ClosePrinter(IntPtr handle);
        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool GetPrinter(IntPtr handle, int level, IntPtr buffer, int size, out int needed);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct PRINTER_INFO_2
        {
            public string pServerName, pPrinterName, pShareName, pPortName, pDriverName, pComment, pLocation;
            public IntPtr pDevMode;
            public string pSepFile, pPrintProcessor, pDatatype, pParameters;
            public IntPtr pSecurityDescriptor;
            public uint Attributes, Priority, DefaultPriority, StartTime, UntilTime, Status, cJobs, AveragePPM;
        }

        static (string driver, uint status, string location, string comment)? SharedQueueInfo(string unc, out int error)
        {
            error = 0;
            if (!OpenPrinter(unc, out var h, IntPtr.Zero)) { error = Marshal.GetLastWin32Error(); return null; }
            try
            {
                GetPrinter(h, 2, IntPtr.Zero, 0, out int needed);
                if (needed <= 0) return ("driver desconocido", 0, "", "");
                var buf = Marshal.AllocHGlobal(needed);
                try
                {
                    if (!GetPrinter(h, 2, buf, needed, out needed)) return ("driver desconocido", 0, "", "");
                    var pi = (PRINTER_INFO_2)Marshal.PtrToStructure(buf, typeof(PRINTER_INFO_2));
                    // 0x2 error, 0x80 offline, 0x400000 no disponible
                    return (pi.pDriverName ?? "driver desconocido", pi.Status & (0x2u | 0x80u | 0x400000u), (pi.pLocation ?? "").Trim(), (pi.pComment ?? "").Trim());
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            finally { ClosePrinter(h); }
        }

        static async Task<long?> PingAsync(string ip, int timeoutMs)
        {
            try
            {
                using (var p = new Ping())
                {
                    var reply = await p.SendPingAsync(ip, timeoutMs).ConfigureAwait(false);
                    return reply.Status == IPStatus.Success ? reply.RoundtripTime : (long?)null;
                }
            }
            catch { return null; }
        }

        static async Task<bool> TcpOpenAsync(string ip, int port, int timeoutMs)
        {
            // nombres de host: IPv4 directo (con el nombre, ConnectAsync puede quedarse en IPv6)
            if (!IPAddress.TryParse(ip, out var addr))
            {
                try { addr = (await Dns.GetHostAddressesAsync(ip).ConfigureAwait(false)).FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork); }
                catch { }
                if (addr == null) return false;
            }
            using (var c = new TcpClient(AddressFamily.InterNetwork))
            {
                var connect = c.ConnectAsync(addr, port);
                if (await Task.WhenAny(connect, Task.Delay(timeoutMs)).ConfigureAwait(false) != connect)
                {
                    _ = connect.ContinueWith(t => t.Exception, TaskContinuationOptions.OnlyOnFaulted); // observar el fallo al cerrar
                    return false;
                }
                try { await connect.ConfigureAwait(false); return c.Connected; }
                catch { return false; }
            }
        }

        // ---------- nombre legible a partir de lo que guarda la impresora ----------
        // nombre de fabrica: el propio modelo ("IM C4500") o derivado de la MAC ("NPID75E14", "BRN30055C")
        static readonly Regex FactoryName = new Regex(@"^[A-Z]{2,4}[0-9A-F]{6,}$", RegexOptions.IgnoreCase);
        static readonly Dictionary<string, string> Words = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["DCH"] = "Dcha", ["DCHA"] = "Dcha", ["DERECHA"] = "Dcha", ["IZQ"] = "Izq", ["IZDA"] = "Izq", ["IZQUIERDA"] = "Izq",
            ["DPCH"] = "Desp.", ["DESP"] = "Desp.", ["DESPACHO"] = "Desp.", ["PLT"] = "Pl.", ["PLANTA"] = "Pl.",
            ["RECEPCION"] = "Recepción", ["DIRECCION"] = "Dirección", ["PUBLICO"] = "Público", ["ADMINISTRACION"] = "Administración",
            ["INFORMATICA"] = "Informática", ["SECRETARIA"] = "Secretaría",
        };

        /// <summary>"PROCESAL_DCH" + "C/ Mayor 1 Plt3 Derecha" -> "Procesal Dcha · P3".</summary>
        public static string Friendly(string name, string location, string model)
        {
            name = (name ?? "").Trim();
            string compact(string s) => Regex.Replace(s ?? "", @"\s", "").ToUpperInvariant();
            bool factory = name.Length == 0 || FactoryName.IsMatch(name) || compact(model).Contains(compact(name));
            string n = factory ? "" : PrettyName(name);
            string loc = PrettyLocation(location ?? "");
            // sin repetir el lado si ya va en el nombre
            if (Regex.IsMatch(n, @"\b(Dcha|Izq)$")) loc = Regex.Replace(loc, @" (dcha|izq)$", "");
            return string.Join(" · ", new[] { n, loc }.Where(x => x.Length > 0));
        }

        static string PrettyName(string n)
        {
            n = Regex.Replace(n, @"^(impresora|printer)\s+", "", RegexOptions.IgnoreCase);
            var words = Regex.Split(n.Replace('_', ' ').Replace('.', ' ').Replace('-', ' '), @"\s+").Where(w => w.Length > 0)
                .Select(w => Words.TryGetValue(w, out var known) ? known : w.All(char.IsDigit) ? w : char.ToUpperInvariant(w[0]) + w.Substring(1).ToLowerInvariant());
            return string.Join(" ", words);
        }

        /// <summary>"C/ Mayor 1 Plt3 Derecha" -> "P3 dcha"; "8ª PLANTA" -> "P8". Sin planta reconocible, el texto tal cual (recortado).</summary>
        static string PrettyLocation(string loc)
        {
            loc = loc.Trim();
            if (loc.Length == 0) return "";
            var m = Regex.Match(loc, @"\b(?:plt|planta|pl)\.?\s*(\d{1,2})|\b(\d{1,2})\s*[ªº°?]?\s*planta", RegexOptions.IgnoreCase);
            if (!m.Success) return loc.Length > 32 ? loc.Substring(0, 32) + "…" : loc;
            var floor = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value;
            var side = Regex.IsMatch(loc, @"\b(derecha|dcha|dch)\b", RegexOptions.IgnoreCase) ? " dcha"
                     : Regex.IsMatch(loc, @"\b(izquierda|izda|izq)\b", RegexOptions.IgnoreCase) ? " izq" : "";
            return "P" + floor + side;
        }

        // ---------- rangos ----------
        public const int MaxHosts = 1024;

        /// <summary>Acepta "192.168.4.0/24", "192.168.4.1-254", "192.168.4.10-192.168.4.80" o una IP suelta.</summary>
        public static List<string> ParseRange(string text)
        {
            text = (text ?? "").Trim();
            uint start, end;
            var slash = text.Split('/');
            if (slash.Length == 2)
            {
                if (!int.TryParse(slash[1].Trim(), out var bits) || bits < 22 || bits > 32) throw new FormatException("Máscara entre /22 y /32.");
                uint mask = bits == 32 ? 0xFFFFFFFFu : ~(0xFFFFFFFFu >> bits);
                start = ToUInt(slash[0].Trim()) & mask;
                end = start | ~mask;
                if (bits <= 30) { start++; end--; }   // sin red ni broadcast
            }
            else
            {
                var dash = text.Split('-');
                if (dash.Length > 2) throw new FormatException("Rango no válido.");
                start = ToUInt(dash[0].Trim());
                if (dash.Length == 1) end = start;
                else
                {
                    var b = dash[1].Trim();
                    if (b.IndexOf('.') >= 0) end = ToUInt(b);
                    else if (uint.TryParse(b, out var last) && last <= 255) end = (start & 0xFFFFFF00u) | last;
                    else throw new FormatException($"Final de rango no válido: {b}");
                }
            }
            if (end < start) throw new FormatException("El final del rango es menor que el inicio.");
            if (end - start + 1 > MaxHosts) throw new FormatException($"Máximo {MaxHosts} direcciones por escaneo.");
            var list = new List<string>((int)(end - start + 1));
            for (uint v = start; v <= end && v >= start; v++) list.Add(FromUInt(v));
            return list;
        }

        /// <summary>Rango /24 de la red de este equipo (la interfaz con puerta de enlace primero).</summary>
        public static string LocalRange()
        {
            try
            {
                var nics = NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                    .OrderByDescending(n => n.GetIPProperties().GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork));
                foreach (var n in nics)
                    foreach (var ua in n.GetIPProperties().UnicastAddresses)
                    {
                        var a = ua.Address;
                        if (a.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(a) || a.ToString().StartsWith("169.254.")) continue;
                        var b = a.GetAddressBytes();
                        return $"{b[0]}.{b[1]}.{b[2]}.1-254";
                    }
            }
            catch { }
            return "";
        }

        public static uint ToUInt(string s)
        {
            if (!IPAddress.TryParse(s, out var a) || a.AddressFamily != AddressFamily.InterNetwork || s.Count(c => c == '.') != 3)
                throw new FormatException($"IP no válida: {s}");
            var b = a.GetAddressBytes();
            return (uint)(b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]);
        }

        static string FromUInt(uint v) => $"{v >> 24}.{(v >> 16) & 255}.{(v >> 8) & 255}.{v & 255}";
    }
}
