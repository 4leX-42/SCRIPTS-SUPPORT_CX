using System;
using System.Windows.Forms;

namespace InstaladorImpresoras
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.ThreadException += (s, e) =>
                ThemedDialog.Info(null, "Error", "Error inesperado", e.Exception.Message);
            Application.Run(new MainForm());
        }
    }
}
