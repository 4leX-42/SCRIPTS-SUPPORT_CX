using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace InstaladorImpresoras
{
    public enum ProbeStatus { Unreachable, NotPrinter, OtherBrand, RicohOtherModel, RicohTarget }

    public sealed class ProbeResult
    {
        public ProbeStatus Status;
        public string Description = "";
        public string Message = "";
        public RicohModel Model;   // modelo soportado detectado (null si no)
    }

    /// <summary>
    /// Comprueba que en una IP hay una impresora y cual es: SNMP (sysDescr / hrDeviceDescr),
    /// con la web de la impresora como alternativa.
    /// </summary>
    public static class PrinterProbe
    {
        public static ProbeResult Probe(string ip)
        {
            var result = new ProbeResult();
            var tRaw = System.Threading.Tasks.Task.Run(() => TcpOpen(ip, 9100, 1500));
            var tHttp = System.Threading.Tasks.Task.Run(() => TcpOpen(ip, 80, 1500));
            var tSnmp = System.Threading.Tasks.Task.Run(() => SnmpDescription(ip));
            var tIpp = System.Threading.Tasks.Task.Run(() => IppMakeAndModel(ip));
            bool raw = tRaw.Result, http = tHttp.Result;
            string snmp = tSnmp.Result, ipp = tIpp.Result;
            // la web solo si SNMP e IPP no han identificado un modelo soportado
            string web = (RicohModels.Detect(snmp) == null && RicohModels.Detect(ipp) == null && http) ? HttpDescription(ip) : null;
            string desc = string.Join(" | ", new[] { snmp, ipp, web }.Where(s => !string.IsNullOrWhiteSpace(s)).Distinct());
            result.Description = desc.Trim();

            if (snmp == null && ipp == null && !raw && !http)
            {
                result.Status = ProbeStatus.Unreachable;
                result.Message = $"No hay ningún dispositivo respondiendo en {ip}.\n\nRevisa la IP en la pantalla de la impresora (Configuración > Info. sistema / Red).";
                return result;
            }
            if (Regex.IsMatch(desc, "ricoh|savin|lanier|gestetner|nashuatec|nrg|rex-rotary|infotec", RegexOptions.IgnoreCase))
            {
                result.Model = RicohModels.Detect(desc);
                result.Status = result.Model != null ? ProbeStatus.RicohTarget : ProbeStatus.RicohOtherModel;
                result.Message = result.Model != null
                    ? $"Detectada: {Short(desc)}"
                    : $"En {ip} hay una Ricoh de un modelo sin driver incluido ({RicohModels.Names}):\n\n{Short(desc)}";
                return result;
            }
            if (desc.Length > 0)
            {
                result.Status = ProbeStatus.OtherBrand;
                result.Message = $"En {ip} hay otro dispositivo, no una Ricoh:\n\n{Short(desc)}";
                return result;
            }
            result.Status = ProbeStatus.NotPrinter;
            result.Message = raw
                ? $"En {ip} responde una impresora, pero no se ha podido identificar el modelo (SNMP desactivado)."
                : $"En {ip} responde un dispositivo, pero no parece una impresora.";
            return result;
        }

        static string Short(string s) => s.Length > 160 ? s.Substring(0, 160) + "…" : s;

        // ---- IPP Get-Printer-Attributes (printer-make-and-model), activo por defecto en Ricoh ----
        static string IppMakeAndModel(string ip)
        {
            foreach (var path in new[] { "/printer", "/ipp/print", "/ipp", "/" })
            {
                try
                {
                    var body = BuildIppRequest($"ipp://{ip}:631{path}");
                    var req = (HttpWebRequest)WebRequest.Create($"http://{ip}:631{path}");
                    req.Method = "POST";
                    req.ContentType = "application/ipp";
                    req.Timeout = 2500;
                    req.ReadWriteTimeout = 2500;
                    req.ContentLength = body.Length;
                    using (var s = req.GetRequestStream()) s.Write(body, 0, body.Length);
                    using (var resp = (HttpWebResponse)req.GetResponse())
                    using (var ms = new System.IO.MemoryStream())
                    {
                        resp.GetResponseStream().CopyTo(ms);
                        var value = IppFindText(ms.ToArray(), "printer-make-and-model");
                        if (!string.IsNullOrWhiteSpace(value)) return value.Trim();
                    }
                }
                catch (WebException ex) when (ex.Status == WebExceptionStatus.ConnectFailure || ex.Status == WebExceptionStatus.Timeout)
                {
                    return null; // puerto 631 cerrado: no insistir con otras rutas
                }
                catch { }
            }
            return null;
        }

        static byte[] BuildIppRequest(string uri)
        {
            var b = new List<byte> { 0x01, 0x01, 0x00, 0x0B, 0x00, 0x00, 0x00, 0x01, 0x01 }; // IPP 1.1, Get-Printer-Attributes, id 1
            void attr(byte tag, string name, string value)
            {
                var n = Encoding.ASCII.GetBytes(name); var v = Encoding.UTF8.GetBytes(value);
                b.Add(tag); b.Add((byte)(n.Length >> 8)); b.Add((byte)n.Length); b.AddRange(n);
                b.Add((byte)(v.Length >> 8)); b.Add((byte)v.Length); b.AddRange(v);
            }
            attr(0x47, "attributes-charset", "utf-8");
            attr(0x48, "attributes-natural-language", "en");
            attr(0x45, "printer-uri", uri);
            attr(0x44, "requested-attributes", "printer-make-and-model");
            b.Add(0x03);
            return b.ToArray();
        }

        static string IppFindText(byte[] d, string name)
        {
            var n = Encoding.ASCII.GetBytes(name);
            for (int i = 3; i + n.Length + 2 < d.Length; i++)
            {
                if (d[i - 2] != 0 || d[i - 1] != n.Length) continue;
                bool hit = true;
                for (int k = 0; k < n.Length && hit; k++) hit = d[i + k] == n[k];
                if (!hit) continue;
                int p = i + n.Length;
                int len = (d[p] << 8) | d[p + 1];
                if (p + 2 + len <= d.Length) return Encoding.UTF8.GetString(d, p + 2, len);
            }
            return null;
        }

        internal static bool TcpOpen(string ip, int port, int timeoutMs)
        {
            try
            {
                using (var c = new TcpClient())
                {
                    var ar = c.BeginConnect(ip, port, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) return false;
                    c.EndConnect(ar);
                    return true;
                }
            }
            catch { return false; }
        }

        // ---- SNMP v1 GET minimo (community "public") ----
        static readonly byte[] OidSysDescr = { 0x2B, 6, 1, 2, 1, 1, 1, 0 };
        static readonly byte[] OidHrDeviceDescr = { 0x2B, 6, 1, 2, 1, 25, 3, 2, 1, 3, 1 };

        static string SnmpDescription(string ip)
        {
            try
            {
                var req = BuildGet("public", OidSysDescr, OidHrDeviceDescr);
                using (var udp = new UdpClient())
                {
                    udp.Client.ReceiveTimeout = 2000;
                    var ep = new IPEndPoint(IPAddress.Parse(ip), 161);
                    for (int attempt = 0; attempt < 2; attempt++)
                    {
                        udp.Send(req, req.Length, ep);
                        try
                        {
                            var remote = new IPEndPoint(IPAddress.Any, 0);
                            var resp = udp.Receive(ref remote);
                            var strings = new List<string>();
                            CollectStrings(resp, 0, resp.Length, strings);
                            // strings[0] = community; el resto son los valores pedidos
                            var vals = strings.Count > 1 ? strings.GetRange(1, strings.Count - 1) : new List<string>();
                            var joined = string.Join(" | ", vals.FindAll(v => v.Trim().Length > 0));
                            return joined.Length > 0 ? joined : null;
                        }
                        catch (SocketException) { }
                    }
                }
            }
            catch { }
            return null;
        }

        static byte[] BuildGet(string community, params byte[][] oids)
        {
            var varbinds = new List<byte>();
            foreach (var oid in oids)
                varbinds.AddRange(Tlv(0x30, Concat(Tlv(0x06, oid), new byte[] { 0x05, 0x00 })));
            var pdu = Tlv(0xA0, Concat(Int(new Random().Next(1, 0x7FFF)), Int(0), Int(0), Tlv(0x30, varbinds.ToArray())));
            return Tlv(0x30, Concat(Int(0), Tlv(0x04, Encoding.ASCII.GetBytes(community)), pdu));
        }

        static byte[] Int(int v)
        {
            var b = new List<byte>();
            do { b.Insert(0, (byte)(v & 0xFF)); v >>= 8; } while (v > 0);
            if ((b[0] & 0x80) != 0) b.Insert(0, 0);
            return Tlv(0x02, b.ToArray());
        }

        static byte[] Tlv(byte tag, byte[] value)
        {
            var r = new List<byte> { tag };
            int len = value.Length;
            if (len < 0x80) r.Add((byte)len);
            else if (len < 0x100) { r.Add(0x81); r.Add((byte)len); }
            else { r.Add(0x82); r.Add((byte)(len >> 8)); r.Add((byte)len); }
            r.AddRange(value);
            return r.ToArray();
        }

        static byte[] Concat(params byte[][] parts)
        {
            var r = new List<byte>();
            foreach (var p in parts) r.AddRange(p);
            return r.ToArray();
        }

        static void CollectStrings(byte[] d, int pos, int end, List<string> output)
        {
            while (pos < end)
            {
                byte tag = d[pos++];
                if (pos >= end) return;
                int len = d[pos++];
                if ((len & 0x80) != 0)
                {
                    int n = len & 0x7F; len = 0;
                    for (int i = 0; i < n && pos < end; i++) len = (len << 8) | d[pos++];
                }
                if (len < 0 || pos + len > end) return;
                if (tag == 0x04) output.Add(Encoding.UTF8.GetString(d, pos, len));
                else if ((tag & 0x20) != 0) CollectStrings(d, pos, pos + len, output);
                pos += len;
            }
        }

        // ---- Web de la impresora (alternativa si SNMP no responde) ----
        static string HttpDescription(string ip)
        {
            foreach (var path in new[] { "/", "/web/guest/es/websys/webArch/mainFrame.cgi" })
            {
                try
                {
                    var req = (HttpWebRequest)WebRequest.Create($"http://{ip}{path}");
                    req.Timeout = 3000;
                    req.ReadWriteTimeout = 3000;
                    req.AllowAutoRedirect = true;
                    using (var resp = (HttpWebResponse)req.GetResponse())
                    using (var sr = new System.IO.StreamReader(resp.GetResponseStream()))
                    {
                        string body = sr.ReadToEnd();
                        string server = resp.Headers["Server"] ?? "";
                        var m = Regex.Match(body, @"(RICOH|Savin|Lanier|Gestetner|nashuatec)[^<""]{0,40}", RegexOptions.IgnoreCase);
                        if (m.Success) return m.Value;
                        var title = Regex.Match(body, @"<title>([^<]{1,80})</title>", RegexOptions.IgnoreCase);
                        var parts = new List<string>();
                        if (server.Length > 0) parts.Add(server);
                        if (title.Success) parts.Add(title.Groups[1].Value.Trim());
                        if (parts.Count > 0) return string.Join(" | ", parts);
                    }
                }
                catch (WebException ex) when (ex.Response is HttpWebResponse r)
                {
                    var server = r.Headers["Server"];
                    if (!string.IsNullOrEmpty(server)) return server;
                }
                catch { }
            }
            return null;
        }
    }
}
