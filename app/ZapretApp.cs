using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public class ZapretApp : Form
{
    private static class Theme
    {
        public static readonly Color Bg = Color.FromArgb(12, 14, 20);
        public static readonly Color Surface = Color.FromArgb(22, 26, 36);
        public static readonly Color SurfaceHover = Color.FromArgb(32, 37, 50);
        public static readonly Color Border = Color.FromArgb(45, 50, 68);
        public static readonly Color Text = Color.FromArgb(240, 244, 255);
        public static readonly Color Muted = Color.FromArgb(148, 156, 178);
        public static readonly Color Accent = Color.FromArgb(99, 102, 241);
        public static readonly Color Accent2 = Color.FromArgb(34, 211, 238);
        public static readonly Color Ok = Color.FromArgb(16, 185, 129);
        public static readonly Color Bad = Color.FromArgb(239, 68, 68);
        public static readonly Color Warn = Color.FromArgb(245, 158, 11);
        public static readonly Color LogBg = Color.FromArgb(10, 12, 18);
    }

    private readonly string rootDir;
    private readonly string utilsDir;
    private readonly string settingsFile;
    private readonly StatusTile tileZapret;
    private readonly StatusTile tileTg;
    private readonly StatusTile tileAdmin;
    private readonly StatusTile tileAuto;
    private readonly StatusTile tileWork;
    private readonly RichTextBox logBox;
    private readonly Button[] lockButtons;
    private readonly Timer statusTimer;
    private readonly NotifyIcon trayIcon;
    private bool reallyExit;
    private bool minimizeToTray = true;
    private bool secretNetDetected;
    private bool statusRefreshRunning;
    private bool startupDone;
    private bool xrayAvailable = true;
    private readonly Label subtitleLabel;
    private readonly Button btnMtproto;

    public ZapretApp(bool startMinimized)
    {
        rootDir = Application.StartupPath;
        utilsDir = Path.Combine(rootDir, "utils");
        settingsFile = Path.Combine(utilsDir, "gui.settings");

        LoadSettings();

        Text = "Otmena";
        ClientSize = new Size(480, 860);
        MinimumSize = new Size(480, 860);
        MaximumSize = new Size(480, 860);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        BackColor = Theme.Bg;
        Font = new Font("Segoe UI", 9.5f);
        DoubleBuffered = true;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

        var header = new Panel
        {
            Location = new Point(0, 0),
            Size = new Size(480, 88),
            BackColor = Theme.Surface
        };
        header.Paint += (s, e) =>
        {
            using (var brush = new LinearGradientBrush(
                new Rectangle(0, 0, header.Width, 3),
                Theme.Accent, Theme.Accent2, LinearGradientMode.Horizontal))
            {
                e.Graphics.FillRectangle(brush, 0, 0, header.Width, 3);
            }
        };

        var title = new Label
        {
            Text = "Otmena",
            ForeColor = Theme.Text,
            Font = new Font("Segoe UI Semibold", 22f),
            AutoSize = true,
            Location = new Point(24, 22),
            BackColor = Color.Transparent
        };
        subtitleLabel = new Label
        {
            Text = "Discord · YouTube · Telegram",
            ForeColor = Theme.Muted,
            Font = new Font("Segoe UI", 10f),
            AutoSize = true,
            Location = new Point(26, 54),
            BackColor = Color.Transparent
        };
        header.Controls.Add(title);
        header.Controls.Add(subtitleLabel);

        tileZapret = new StatusTile("Discord / YouTube", 24, 104, 136);
        tileTg = new StatusTile("Telegram", 172, 104, 136);
        tileAdmin = new StatusTile("Права", 320, 104, 136);
        tileAuto = new StatusTile("Автозапуск", 98, 168, 136);
        tileWork = new StatusTile("Work mode", 246, 168, 136);

        var lblActions = SectionLabel("Действия", 240);
        var btnStart = MakePrimaryButton("▶  Запустить", 24, 264, 432, 48);
        var btnStop = MakeGhostButton("■  Остановить", 24, 322, 210, 40);
        var btnTest = MakeGhostButton("⚡  Проверить", 246, 322, 210, 40);

        var lblTg = SectionLabel("Telegram", 376);
        btnMtproto = MakeAccentButton("Добавить MTProto в Telegram", 24, 400, 432, 40);

        var lblSys = SectionLabel("Система", 454);
        var btnAutoOn = MakeGhostButton("Автозапуск ВКЛ", 24, 478, 210, 36);
        var btnAutoOff = MakeGhostButton("Автозапуск ВЫКЛ", 246, 478, 210, 36);
        var btnWork = MakeGhostButton("Work mode", 24, 522, 210, 36);
        var btnAdmin = MakeGhostButton("От администратора", 246, 522, 210, 36);
        var btnCursor = MakeGhostButton("Cursor exclude", 24, 566, 210, 36);
        var btnDiag = MakeGhostButton("Диагностика", 246, 566, 210, 36);
        var btnUpdates = MakeGhostButton("Обновления", 24, 610, 210, 36);
        var btnClean = MakeGhostButton("Выключить всё", 246, 610, 210, 36);

        var btnDelete = new Button
        {
            Text = "Удалить Otmena с компьютера",
            Location = new Point(24, 658),
            Size = new Size(432, 34),
            FlatStyle = FlatStyle.Flat,
            BackColor = Theme.Bg,
            ForeColor = Color.FromArgb(248, 113, 113),
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 9f)
        };
        btnDelete.FlatAppearance.BorderColor = Color.FromArgb(80, 45, 45);
        btnDelete.FlatAppearance.BorderSize = 1;

        var logPanel = new Panel
        {
            Location = new Point(24, 704),
            Size = new Size(432, 140),
            BackColor = Theme.LogBg
        };
        logPanel.Paint += (s, e) =>
        {
            using (var pen = new Pen(Theme.Border))
                e.Graphics.DrawRectangle(pen, 0, 0, logPanel.Width - 1, logPanel.Height - 1);
        };
        var logTitle = new Label
        {
            Text = "Журнал",
            ForeColor = Theme.Muted,
            Font = new Font("Segoe UI Semibold", 8.5f),
            Location = new Point(10, 6),
            AutoSize = true,
            BackColor = Color.Transparent
        };
        logBox = new RichTextBox
        {
            Location = new Point(8, 24),
            Size = new Size(416, 108),
            ReadOnly = true,
            BorderStyle = BorderStyle.None,
            BackColor = Theme.LogBg,
            ForeColor = Color.FromArgb(203, 213, 225),
            Font = new Font("Cascadia Mono", 8.25f),
            ScrollBars = RichTextBoxScrollBars.Vertical
        };
        logPanel.Controls.Add(logTitle);
        logPanel.Controls.Add(logBox);

        lockButtons = new[]
        {
            btnStart, btnStop, btnTest, btnAutoOn, btnAutoOff, btnWork, btnAdmin,
            btnCursor, btnDiag, btnUpdates, btnClean, btnMtproto, btnDelete
        };

        btnStart.Click += (s, e) => RunLauncher("start", "Запуск...");
        btnStop.Click += (s, e) => RunLauncher("stop", "Остановка...");
        btnTest.Click += (s, e) => RunTest();
        btnAutoOn.Click += (s, e) => RunPsScript("install-autostart-smart.ps1", false, "Автозапуск включён.", "Не удалось включить автозапуск.");
        btnAutoOff.Click += (s, e) => RunPsScript("remove-autostart.ps1", false, "Автозапуск выключен.", "Ошибка отключения автозапуска.");
        btnWork.Click += (s, e) => RunPsScript("toggle-work-mode.ps1", false, "Work mode переключён.", "Не удалось переключить work mode.");
        btnAdmin.Click += (s, e) => RestartAsAdmin();
        btnCursor.Click += (s, e) => RunPsScript("update-cursor-exclude.ps1", false, "Cursor exclude обновлён.", "Ошибка Cursor exclude.");
        btnDiag.Click += (s, e) => CopyDiagnostics();
        btnUpdates.Click += (s, e) => CheckUpdates();
        btnClean.Click += (s, e) => RunPsScript("uninstall-all.ps1", false, "Всё выключено.", "Ошибка при остановке.");
        btnMtproto.Click += (s, e) => RunMtProto();
        btnDelete.Click += (s, e) => ConfirmDelete();

        Controls.AddRange(new Control[]
        {
            header, tileZapret, tileTg, tileAdmin, tileAuto, tileWork,
            lblActions, btnStart, btnStop, btnTest,
            lblTg, btnMtproto,
            lblSys, btnAutoOn, btnAutoOff, btnWork, btnAdmin, btnCursor, btnDiag, btnUpdates, btnClean,
            btnDelete, logPanel
        });

        trayIcon = new NotifyIcon
        {
            Icon = Icon,
            Text = "Otmena",
            Visible = true
        };
        var trayMenu = new ContextMenuStrip();
        trayMenu.Items.Add("Открыть", null, (s, e) => ShowFromTray());
        trayMenu.Items.Add("Запустить", null, (s, e) => RunLauncher("start", "Запуск из трея..."));
        trayMenu.Items.Add("Остановить", null, (s, e) => RunLauncher("stop", "Остановка из трея..."));
        trayMenu.Items.Add(new ToolStripSeparator());
        trayMenu.Items.Add("Выход", null, (s, e) => { reallyExit = true; Close(); });
        trayIcon.ContextMenuStrip = trayMenu;
        trayIcon.DoubleClick += (s, e) => ShowFromTray();

        FormClosing += (s, e) =>
        {
            if (!reallyExit && minimizeToTray)
            {
                e.Cancel = true;
                Hide();
                trayIcon.ShowBalloonTip(2000, "Otmena", "Работает в фоне. Двойной клик — открыть.", ToolTipIcon.Info);
            }
            else
            {
                trayIcon.Visible = false;
                trayIcon.Dispose();
            }
        };

        statusTimer = new Timer { Interval = 8000 };
        statusTimer.Tick += (s, e) => RefreshStatusAsync(true);

        Load += (s, e) =>
        {
            AppendLog("Готов к работе.", Theme.Muted);
            if (!IsAdmin()) AppendLog("Запусти от администратора для DS/YT.", Theme.Warn);
            tileZapret.SetState(false, "…", "…");
            tileTg.SetState(false, "…", "…");
            tileAdmin.SetState(IsAdmin(), IsAdmin() ? "Админ" : "…", "Нет прав");
            tileAuto.SetState(false, "…", "…");
            tileWork.SetState(false, "…", "…");
            BeginStartup(startMinimized);
        };
    }

    private void BeginStartup(bool startMinimized)
    {
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) =>
        {
            var xrayOut = RunPsCapture("ensure-xray.ps1");
            var env = RunPsCapture("detect-environment.ps1");
            var status = RunPsCapture("get-status.ps1");
            e.Result = new object[] { xrayOut, env, status };
        };
        bw.RunWorkerCompleted += (s, e) =>
        {
            if (IsDisposed) return;
            startupDone = true;
            if (e.Error != null)
            {
                AppendLog("Ошибка загрузки: " + e.Error.Message, Theme.Bad);
                statusTimer.Start();
                return;
            }

            var parts = e.Result as object[];
            var xrayOut = parts != null && parts.Length > 0 ? parts[0] as string : string.Empty;
            var env = parts != null && parts.Length > 1 ? parts[1] as string : string.Empty;
            var status = parts != null && parts.Length > 2 ? parts[2] as string : string.Empty;

            if (!string.IsNullOrEmpty(xrayOut) && xrayOut.Contains("XRAY_OK=1"))
                AppendLog("xray установлен — Telegram через VLESS.", Theme.Ok);
            else if (!string.IsNullOrEmpty(xrayOut) && xrayOut.Contains("XRAY_OK=0"))
                AppendLog("xray не скачался — положи xray-windows-64.zip в telegram-vless\\bin или MTProto.", Theme.Warn);

            secretNetDetected = env.Contains("SECRETNET=1");
            if (secretNetDetected)
                AppendLog("Secret Net обнаружен — Work mode рекомендуется.", Theme.Warn);

            xrayAvailable = env.Contains("XRAY=1");
            UpdateTelegramUi();

            ApplyStatusOutput(status);
            MaybeFirstRun(env);
            statusTimer.Start();

            if (startMinimized && minimizeToTray)
            {
                Hide();
                trayIcon.ShowBalloonTip(2000, "Otmena", "Запущен в фоне.", ToolTipIcon.Info);
            }
        };
        bw.RunWorkerAsync();
    }

    private void LoadSettings()
    {
        try
        {
            if (!File.Exists(settingsFile)) return;
            foreach (var line in File.ReadAllLines(settingsFile))
            {
                if (line.StartsWith("minimizeToTray=0")) minimizeToTray = false;
            }
        }
        catch { }
    }

    private void SaveSettings()
    {
        try
        {
            File.WriteAllText(settingsFile, "minimizeToTray=" + (minimizeToTray ? "1" : "0"), Encoding.UTF8);
        }
        catch { }
    }

    private void ShowFromTray()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private Label SectionLabel(string text, int y)
    {
        return new Label
        {
            Text = text.ToUpperInvariant(),
            ForeColor = Theme.Muted,
            Font = new Font("Segoe UI Semibold", 8f),
            AutoSize = true,
            Location = new Point(24, y),
            BackColor = Color.Transparent
        };
    }

    private Button MakePrimaryButton(string text, int x, int y, int w, int h)
    {
        var b = new Button
        {
            Text = text,
            Location = new Point(x, y),
            Size = new Size(w, h),
            FlatStyle = FlatStyle.Flat,
            BackColor = Theme.Accent,
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI Semibold", 11f)
        };
        b.FlatAppearance.BorderSize = 0;
        WireHover(b, Theme.Accent, Color.FromArgb(129, 132, 255));
        return b;
    }

    private Button MakeAccentButton(string text, int x, int y, int w, int h)
    {
        var b = new Button
        {
            Text = text,
            Location = new Point(x, y),
            Size = new Size(w, h),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(30, 58, 72),
            ForeColor = Theme.Accent2,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI Semibold", 9.5f)
        };
        b.FlatAppearance.BorderColor = Color.FromArgb(34, 100, 120);
        b.FlatAppearance.BorderSize = 1;
        WireHover(b, Color.FromArgb(30, 58, 72), Color.FromArgb(40, 72, 88));
        return b;
    }

    private Button MakeGhostButton(string text, int x, int y, int w, int h)
    {
        var b = new Button
        {
            Text = text,
            Location = new Point(x, y),
            Size = new Size(w, h),
            FlatStyle = FlatStyle.Flat,
            BackColor = Theme.Surface,
            ForeColor = Theme.Text,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 9f)
        };
        b.FlatAppearance.BorderColor = Theme.Border;
        b.FlatAppearance.BorderSize = 1;
        WireHover(b, Theme.Surface, Theme.SurfaceHover);
        return b;
    }

    private void WireHover(Button b, Color normal, Color hover)
    {
        b.MouseEnter += (s, e) => b.BackColor = hover;
        b.MouseLeave += (s, e) => b.BackColor = normal;
    }

    private bool IsAdmin()
    {
        var id = WindowsIdentity.GetCurrent();
        var p = new WindowsPrincipal(id);
        return p.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private void AppendLog(string text, Color color)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action(() => AppendLog(text, color)));
            return;
        }
        logBox.SelectionStart = logBox.TextLength;
        logBox.SelectionColor = color;
        logBox.AppendText(DateTime.Now.ToString("HH:mm") + "  " + text + Environment.NewLine);
        logBox.SelectionColor = logBox.ForeColor;
        logBox.ScrollToCaret();
    }

    private void SetBusy(bool busy)
    {
        foreach (var b in lockButtons) b.Enabled = !busy;
    }

    private void RunPs(string args, Action<int> onDone)
    {
        SetBusy(true);
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) =>
        {
            e.Result = RunHidden("powershell.exe",
                "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass " + args);
        };
        bw.RunWorkerCompleted += (s, e) =>
        {
            SetBusy(false);
            if (e.Error != null)
            {
                AppendLog("Ошибка: " + e.Error.Message, Theme.Bad);
            }
            else
            {
                var code = e.Result is int ? (int)e.Result : 1;
                if (onDone != null) onDone(code);
            }
            RefreshStatusAsync(true);
        };
        bw.RunWorkerAsync();
    }

    private int RunHidden(string file, string args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = file,
            Arguments = args,
            WorkingDirectory = rootDir,
            CreateNoWindow = true,
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        var p = Process.Start(psi);
        p.WaitForExit();
        return p.ExitCode;
    }

    private string RunPsCapture(string scriptName)
    {
        var script = Path.Combine(utilsDir, scriptName);
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"",
            WorkingDirectory = rootDir,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            StandardOutputEncoding = Encoding.UTF8
        };
        using (var p = Process.Start(psi))
        {
            var output = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            return output ?? string.Empty;
        }
    }

    private void RunLauncher(string action, string startMsg)
    {
        AppendLog(startMsg, Theme.Accent2);
        var launcher = Path.Combine(utilsDir, "launcher.ps1");
        RunPs("-File \"" + launcher + "\" -Action " + action, code =>
        {
            var tail = ReadLauncherTail(8);
            if (action == "stop")
            {
                AppendLog(code == 0 ? "Остановлено." : "Ошибка остановки (код " + code + ").",
                    code == 0 ? Theme.Ok : Theme.Bad);
            }
            else if (code == 0)
            {
                AppendLog("Готово.", Theme.Ok);
            }
            else
            {
                AppendLog("Не всё запустилось (код " + code + ").", Theme.Bad);
                if (secretNetDetected)
                    AppendLog("Secret Net может блокировать WinDivert — попробуй только Telegram.", Theme.Warn);
            }
            if (!string.IsNullOrEmpty(tail)) AppendLog(tail, Theme.Muted);
            if (action == "start")
            {
                MaybeCorpTelegramHint();
                if (code != 0 && !xrayAvailable)
                    ShowMtProtoSetup(LoadMtProtoConfig());
            }
        });
    }

    private void RunTest()
    {
        AppendLog("Проверка всех способов...", Theme.Accent2);
        SetBusy(true);
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) =>
        {
            e.Result = RunPsCapture("get-test-results.ps1");
        };
        bw.RunWorkerCompleted += (s, e) =>
        {
            SetBusy(false);
            if (e.Error != null)
            {
                AppendLog("Ошибка проверки: " + e.Error.Message, Theme.Bad);
                RefreshStatusAsync(false);
                return;
            }

            var output = e.Result as string ?? string.Empty;
            var exitCode = 1;
            string bestZapret = null;
            string bestTg = null;

            foreach (var line in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.StartsWith("RESULT="))
                {
                    var parts = line.Substring(7).Split('|');
                    if (parts.Length >= 4)
                    {
                        var ok = parts[2] == "1";
                        AppendLog((ok ? "✓ " : "✗ ") + parts[0] + " / " + parts[1] + ": " + parts[3],
                            ok ? Theme.Ok : Theme.Bad);
                    }
                }
                else if (line.StartsWith("BEST_ZAPRET="))
                {
                    bestZapret = line.Substring(12);
                }
                else if (line.StartsWith("BEST_TG="))
                {
                    bestTg = line.Substring(8);
                }
                else if (line.StartsWith("EXIT="))
                {
                    int.TryParse(line.Substring(5), out exitCode);
                }
            }

            if (!string.IsNullOrEmpty(bestZapret))
                AppendLog("Лучший DS/YT: " + bestZapret, Theme.Ok);
            else
                AppendLog("DS/YT: нет рабочих способов.", Theme.Bad);

            if (!string.IsNullOrEmpty(bestTg))
                AppendLog("Лучший Telegram: " + bestTg, Theme.Ok);
            else
                AppendLog("Telegram: нет рабочих способов.", Theme.Bad);

            AppendLog(exitCode == 0 ? "Проверка завершена." : "Проверка: проблемы (код " + exitCode + ").",
                exitCode == 0 ? Theme.Ok : Theme.Warn);
            RefreshStatusAsync(false);
        };
        bw.RunWorkerAsync();
    }

    private string ReadLauncherTail(int lines)
    {
        try
        {
            var log = Path.Combine(utilsDir, "launcher.log");
            if (!File.Exists(log)) return string.Empty;
            var all = File.ReadAllLines(log);
            if (all.Length == 0) return string.Empty;
            var take = Math.Min(lines, all.Length);
            return string.Join(Environment.NewLine, all, all.Length - take, take);
        }
        catch { return string.Empty; }
    }

    private sealed class ScriptResult
    {
        public int ExitCode;
        public string Output = string.Empty;
    }

    private ScriptResult RunScriptCapture(string scriptName, string extraArgs = null)
    {
        var script = Path.Combine(utilsDir, scriptName);
        var args = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"";
        if (!string.IsNullOrEmpty(extraArgs))
            args += " " + extraArgs;
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = args,
            WorkingDirectory = rootDir,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            StandardOutputEncoding = Encoding.UTF8
        };
        using (var p = Process.Start(psi))
        {
            var output = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            return new ScriptResult { ExitCode = p.ExitCode, Output = output ?? string.Empty };
        }
    }

    private void RunMtProto()
    {
        var cfg = LoadMtProtoConfig();
        if (!xrayAvailable)
        {
            AppendLog("Настройки MTProto для Telegram...", Theme.Accent2);
            ShowMtProtoSetup(cfg);
        }
        else
        {
            AppendLog("MTProto...", Theme.Accent2);
        }

        SetBusy(true);
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) => { e.Result = RunScriptCapture("set-telegram-mtproto.ps1"); };
        bw.RunWorkerCompleted += (s, e) =>
        {
            SetBusy(false);
            if (e.Error != null)
            {
                AppendLog("Ошибка: " + e.Error.Message, Theme.Bad);
                return;
            }

            var result = e.Result as ScriptResult;
            if (result == null) return;

            string server = cfg.Server, port = cfg.Port, secret = cfg.Secret;
            foreach (var line in result.Output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.StartsWith("SERVER=")) server = line.Substring(7);
                if (line.StartsWith("PORT=")) port = line.Substring(5);
                if (line.StartsWith("SECRET=")) secret = line.Substring(7);
            }

            if (result.ExitCode == 0)
            {
                AppendLog("MTProto добавлен — включи proxy-dag.ru в Telegram.", Theme.Ok);
                return;
            }

            if (result.ExitCode == 2)
            {
                AppendLog("tg:// не открылся — вставь данные из окна в Telegram.", Theme.Warn);
                ShowMtProtoSetup(new MtProtoConfig { Server = server, Port = port, Secret = secret });
                return;
            }

            AppendLog("Ошибка MTProto (код " + result.ExitCode + ").", Theme.Bad);
            ShowMtProtoSetup(new MtProtoConfig { Server = server, Port = port, Secret = secret });
        };
        bw.RunWorkerAsync();
    }

    private sealed class MtProtoConfig
    {
        public string Server = "proxy-dag.ru";
        public string Port = "443";
        public string Secret = "";
    }

    private MtProtoConfig LoadMtProtoConfig()
    {
        var cfg = new MtProtoConfig();
        try
        {
            var path = Path.Combine(utilsDir, "telegram-mtproto.json");
            if (!File.Exists(path)) return cfg;
            var json = File.ReadAllText(path, Encoding.UTF8);
            var s = ReadJsonString(json, "server");
            var p = ReadJsonString(json, "port");
            var sec = ReadJsonString(json, "secret");
            if (!string.IsNullOrEmpty(s)) cfg.Server = s;
            if (!string.IsNullOrEmpty(p)) cfg.Port = p;
            if (!string.IsNullOrEmpty(sec)) cfg.Secret = sec;
        }
        catch { }
        return cfg;
    }

    private static string ReadJsonString(string json, string key)
    {
        var m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"([^\"]*)\"");
        return m.Success ? m.Groups[1].Value : "";
    }

    private void ShowMtProtoSetup(MtProtoConfig cfg)
    {
        TelegramMtprotoDialog.Show(this, cfg.Server, cfg.Port, cfg.Secret);
    }

    private void UpdateTelegramUi()
    {
        if (subtitleLabel == null || btnMtproto == null) return;
        if (!xrayAvailable)
        {
            subtitleLabel.Text = "Discord · YouTube · Telegram (MTProto)";
            btnMtproto.Text = "Настройки Telegram — скопировать MTProto";
        }
        else
        {
            subtitleLabel.Text = "Discord · YouTube · Telegram";
            btnMtproto.Text = "Добавить MTProto в Telegram";
        }
    }

    private void MaybeCorpTelegramHint()
    {
        if (xrayAvailable) return;
        var flag = Path.Combine(utilsDir, "corp_tg_hint.done");
        if (File.Exists(flag)) return;

        var cfg = LoadMtProtoConfig();
        var ans = MessageBox.Show(
            "На этом ПК нет xray.exe (часто на рабочих машинах).\n\n" +
            "Telegram работает через MTProto.\n" +
            "Открыть окно с сервером, портом и secret для копирования?",
            "Telegram без xray",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Information);
        if (ans == DialogResult.Yes)
            ShowMtProtoSetup(cfg);
        try { File.WriteAllText(flag, DateTime.Now.ToString("o"), Encoding.UTF8); } catch { }
    }

    private void RunPsScript(string name, bool needAdmin, string doneMsg, string failMsg)
    {
        if (needAdmin && !IsAdmin())
        {
            AppendLog("Нужны права администратора.", Theme.Bad);
            return;
        }
        AppendLog(name.Replace(".ps1", "") + "...", Theme.Accent2);
        var script = Path.Combine(utilsDir, name);
        RunPs("-File \"" + script + "\"", code =>
        {
            if (code == 0)
                AppendLog(doneMsg, Theme.Ok);
            else
                AppendLog(failMsg + " (код " + code + ")", Theme.Bad);
        });
    }

    private void CopyDiagnostics()
    {
        AppendLog("Сбор диагностики...", Theme.Accent2);
        SetBusy(true);
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) => { e.Result = RunPsCapture("export-diagnostics.ps1"); };
        bw.RunWorkerCompleted += (s, e) =>
        {
            SetBusy(false);
            if (e.Error != null)
            {
                AppendLog("Ошибка: " + e.Error.Message, Theme.Bad);
                return;
            }
            try
            {
                Clipboard.SetText(e.Result as string ?? string.Empty);
                AppendLog("Диагностика скопирована в буфер обмена.", Theme.Ok);
            }
            catch
            {
                AppendLog("Не удалось скопировать в буфер.", Theme.Bad);
            }
        };
        bw.RunWorkerAsync();
    }

    private void CheckUpdates()
    {
        AppendLog("Проверка обновлений...", Theme.Accent2);
        SetBusy(true);
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) => { e.Result = RunScriptCapture("check-updates.ps1", "-Quiet"); };
        bw.RunWorkerCompleted += (s, e) =>
        {
            SetBusy(false);
            if (e.Error != null)
            {
                AppendLog("Ошибка: " + e.Error.Message, Theme.Bad);
                return;
            }

            var result = e.Result as ScriptResult;
            if (result == null) return;

            string localV = null, remoteV = null, source = null, packageUrl = null, updateError = null;
            var update = false;
            foreach (var line in result.Output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.StartsWith("VERSION_LOCAL=")) localV = line.Substring(14);
                if (line.StartsWith("VERSION_REMOTE=")) remoteV = line.Substring(15);
                if (line.StartsWith("UPDATE_SOURCE=")) source = line.Substring(14);
                if (line.StartsWith("PACKAGE_URL=")) packageUrl = line.Substring(12);
                if (line.StartsWith("UPDATE_ERROR=")) updateError = line.Substring(13);
                if (line.StartsWith("UPDATE_AVAILABLE=1")) update = true;
            }

            if (!string.IsNullOrEmpty(updateError))
            {
                AppendLog("Ошибка проверки: " + updateError, Theme.Warn);
                AppendLog("Проверь utils\\update-config.json (githubRepo).", Theme.Muted);
                return;
            }

            if (string.IsNullOrEmpty(remoteV))
            {
                AppendLog("GitHub недоступен с этого ПК.", Theme.Warn);
                AppendLog("Скачай вручную: github.com/Qylosez/otmena-releases/releases", Theme.Muted);
                return;
            }

            if (!update)
            {
                AppendLog("Версия актуальна: " + localV + ".", Theme.Ok);
                return;
            }

            AppendLog("Доступна версия " + remoteV + " (сейчас " + localV + ").", Theme.Warn);

            if (source == "custom" || source == "github")
            {
                var srcLabel = source == "github" ? "GitHub" : "сервер";
                var ans = MessageBox.Show(
                    "Установить обновление " + remoteV + " (" + srcLabel + ")?\n\nOtmena закроется и перезапустится.",
                    "Обновление Otmena",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);
                if (ans != DialogResult.Yes) return;
                InstallUpdate(packageUrl);
                return;
            }

            AppendLog("Нет настроенного канала — укажи githubRepo в update-config.json", Theme.Warn);
        };
        bw.RunWorkerAsync();
    }

    private void InstallUpdate(string packageUrl)
    {
        AppendLog("Установка обновления...", Theme.Accent2);
        SetBusy(true);
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) =>
        {
            var args = "-File \"" + Path.Combine(utilsDir, "apply-update.ps1") + "\" -Quiet";
            if (!string.IsNullOrEmpty(packageUrl))
                args += " -PackageUrl \"" + packageUrl + "\"";
            e.Result = RunHidden("powershell.exe",
                "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " + args);
        };
        bw.RunWorkerCompleted += (s, e) =>
        {
            SetBusy(false);
            var code = e.Result is int ? (int)e.Result : 1;
            if (code == 0)
            {
                AppendLog("Обновление запланировано — перезапуск...", Theme.Ok);
                reallyExit = true;
                Close();
            }
            else
            {
                AppendLog("Ошибка установки (код " + code + ").", Theme.Bad);
            }
        };
        bw.RunWorkerAsync();
    }

    private void MaybeFirstRun(string env)
    {
        var flag = Path.Combine(utilsDir, "first_run.done");
        if (File.Exists(flag)) return;

        secretNetDetected = env.Contains("SECRETNET=1");
        var workMode = env.Contains("WORK=1");
        var noXray = env.Contains("XRAY=0");

        var sb = new StringBuilder();
        sb.AppendLine("Добро пожаловать в Otmena!");
        sb.AppendLine();
        if (secretNetDetected)
            sb.AppendLine("• Обнаружен Secret Net — рекомендуется Work mode (без службы Windows).");
        if (!IsAdmin())
            sb.AppendLine("• Для Discord/YouTube нужны права администратора.");
        if (noXray)
            sb.AppendLine("• xray ставится при первом запуске. Если не скачался — загрузи xray-windows-64.zip в Releases.");
        sb.AppendLine();
        sb.AppendLine("Свернуть в трей при закрытии окна?");

        var ans = MessageBox.Show(sb.ToString(), "Первый запуск Otmena",
            MessageBoxButtons.YesNo, MessageBoxIcon.Information);
        minimizeToTray = ans == DialogResult.Yes;
        SaveSettings();

        if (secretNetDetected && !workMode)
        {
            var wm = MessageBox.Show(
                "Включить Work mode для этого ПК?\n(без службы Windows — подходит для Secret Net)",
                "Work mode", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (wm == DialogResult.Yes)
            {
                var bw = new BackgroundWorker();
                bw.DoWork += (s, e) =>
                {
                    RunHidden("powershell.exe",
                        "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" +
                        Path.Combine(utilsDir, "toggle-work-mode.ps1") + "\" -Action on");
                };
                bw.RunWorkerCompleted += (s, e) => RefreshStatusAsync(false);
                bw.RunWorkerAsync();
            }
        }

        try { File.WriteAllText(flag, DateTime.Now.ToString("o"), Encoding.UTF8); } catch { }

        if (noXray)
        {
            var tg = MessageBox.Show(
                "Открыть окно с настройками MTProto для Telegram?",
                "Telegram",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);
            if (tg == DialogResult.Yes)
                ShowMtProtoSetup(LoadMtProtoConfig());
        }
    }

    private void ConfirmDelete()
    {
        var ans = MessageBox.Show(
            "Остановить всё и удалить папку Otmena?\n\nОтменить будет нельзя.",
            "Удаление Otmena",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);
        if (ans != DialogResult.Yes) return;

        if (!IsAdmin())
        {
            AppendLog("Нужен администратор.", Theme.Bad);
            RestartAsAdmin();
            return;
        }

        reallyExit = true;
        AppendLog("Удаление...", Theme.Warn);
        var script = Path.Combine(utilsDir, "uninstall-all.ps1");
        var code = RunHidden("powershell.exe",
            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\" -DeleteFolder -Quiet");

        if (code == 0)
        {
            MessageBox.Show("Папка будет удалена через несколько секунд.", "Otmena",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        else
        {
            AppendLog("Ошибка удаления (код " + code + ").", Theme.Bad);
        }
        Close();
    }

    private void RestartAsAdmin()
    {
        if (IsAdmin())
        {
            AppendLog("Уже от администратора.", Theme.Ok);
            return;
        }
        try
        {
            Process.Start(new ProcessStartInfo(Application.ExecutablePath)
            {
                UseShellExecute = true,
                Verb = "runas"
            });
            reallyExit = true;
            Close();
        }
        catch
        {
            AppendLog("Не удалось запросить права админа.", Theme.Bad);
        }
    }

    private void RefreshStatusAsync(bool skipIfBusy)
    {
        if (!startupDone) return;
        if (statusRefreshRunning && skipIfBusy) return;

        statusRefreshRunning = true;
        var bw = new BackgroundWorker();
        bw.DoWork += (s, e) => { e.Result = RunPsCapture("get-status.ps1"); };
        bw.RunWorkerCompleted += (s, e) =>
        {
            statusRefreshRunning = false;
            if (IsDisposed || e.Error != null) return;
            ApplyStatusOutput(e.Result as string);
        };
        bw.RunWorkerAsync();
    }

    private void ApplyStatusOutput(string output)
    {
        if (string.IsNullOrEmpty(output)) return;
        if (InvokeRequired)
        {
            BeginInvoke(new Action(() => ApplyStatusOutput(output)));
            return;
        }

        bool zapret = false, tg = false, admin = false, auto = false, work = false;
        var hasXray = xrayAvailable;
        string autoType = "none";
        foreach (var line in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            if (line.StartsWith("ZAPRET=1")) zapret = true;
            if (line.StartsWith("TG=1")) tg = true;
            if (line.StartsWith("ADMIN=1")) admin = true;
            if (line.StartsWith("AUTO=1")) auto = true;
            if (line.StartsWith("WORK=1")) work = true;
            if (line.StartsWith("AUTO_TYPE=")) autoType = line.Substring(10);
            if (line.StartsWith("XRAY=0")) { hasXray = false; xrayAvailable = false; }
            if (line.StartsWith("XRAY=1")) { hasXray = true; xrayAvailable = true; }
        }
        UpdateTelegramUi();
        tileZapret.SetState(zapret, "Онлайн", "Выключен");
        if (!hasXray && !tg)
            tileTg.SetState(false, "MTProto", "Настроить");
        else
            tileTg.SetState(tg, "Онлайн", "Выключен");
        tileAdmin.SetState(admin, "Админ", "Нет прав");
        var autoOn = auto ? (autoType == "task" ? "Задача" : autoType == "startup" ? "Startup" : "Включён") : "Выключен";
        tileAuto.SetState(auto, autoOn, "Выключен");
        tileWork.SetState(work, "Включён", "Обычный");
    }

    [STAThread]
    public static void Main(string[] args)
    {
        var startMinimized = false;
        if (args != null)
        {
            foreach (var a in args)
            {
                if (string.Equals(a, "/minimized", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(a, "-minimized", StringComparison.OrdinalIgnoreCase))
                {
                    startMinimized = true;
                }
            }
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ZapretApp(startMinimized));
    }
}

internal static class TelegramMtprotoDialog
{
    public static void Show(IWin32Window owner, string server, string port, string secret)
    {
        using (var f = new Form())
        {
            f.Text = "Telegram — MTProto";
            f.FormBorderStyle = FormBorderStyle.FixedDialog;
            f.MaximizeBox = false;
            f.MinimizeBox = false;
            f.StartPosition = FormStartPosition.CenterParent;
            f.ClientSize = new Size(440, 320);
            f.BackColor = Color.FromArgb(22, 26, 36);
            f.Font = new Font("Segoe UI", 9.5f);

            var hint = new Label
            {
                Text = "Telegram Desktop → Настройки → Данные и память →\r\n" +
                    "Использование прокси → Добавить прокси → MTProto\r\n\r\n" +
                    "Нажми «Копировать» у каждого поля и вставь в Telegram.",
                ForeColor = Color.FromArgb(148, 156, 178),
                Location = new Point(16, 12),
                Size = new Size(408, 56),
                BackColor = Color.Transparent
            };
            f.Controls.Add(hint);

            var y = 78;
            AddRow(f, "Сервер", server, ref y);
            AddRow(f, "Порт", port, ref y);
            AddRow(f, "Secret", secret, ref y);

            var btnAll = new Button
            {
                Text = "Скопировать всё",
                Location = new Point(16, 248),
                Size = new Size(130, 32),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(99, 102, 241),
                ForeColor = Color.White,
                Cursor = Cursors.Hand
            };
            btnAll.FlatAppearance.BorderSize = 0;
            btnAll.Click += (s, e) =>
            {
                CopyText("Сервер: " + server + "\r\nПорт: " + port + "\r\nSecret: " + secret);
                MessageBox.Show(f, "Все поля скопированы.", "Буфер обмена", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            f.Controls.Add(btnAll);

            var btnOk = new Button
            {
                Text = "Готово",
                Location = new Point(334, 248),
                Size = new Size(90, 32),
                DialogResult = DialogResult.OK,
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(45, 50, 68),
                ForeColor = Color.White,
                Cursor = Cursors.Hand
            };
            btnOk.FlatAppearance.BorderSize = 0;
            f.Controls.Add(btnOk);
            f.AcceptButton = btnOk;

            f.ShowDialog(owner);
        }
    }

    private static void AddRow(Form f, string label, string value, ref int y)
    {
        var lbl = new Label
        {
            Text = label,
            ForeColor = Color.FromArgb(148, 156, 178),
            Location = new Point(16, y),
            AutoSize = true,
            BackColor = Color.Transparent
        };
        var box = new TextBox
        {
            Text = value,
            ReadOnly = true,
            Location = new Point(16, y + 18),
            Size = new Size(308, 24),
            BackColor = Color.FromArgb(12, 14, 20),
            ForeColor = Color.FromArgb(240, 244, 255),
            BorderStyle = BorderStyle.FixedSingle
        };
        var btn = new Button
        {
            Text = "Копировать",
            Location = new Point(332, y + 16),
            Size = new Size(92, 28),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(45, 50, 68),
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            Tag = value
        };
        btn.FlatAppearance.BorderSize = 0;
        btn.Click += (s, e) =>
        {
            var v = (string)((Button)s).Tag;
            CopyText(v);
            MessageBox.Show(f, label + " скопирован.", "Буфер обмена", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        f.Controls.Add(lbl);
        f.Controls.Add(box);
        f.Controls.Add(btn);
        y += 52;
    }

    private static void CopyText(string text)
    {
        try { Clipboard.SetText(text); } catch { }
    }
}

internal class StatusTile : Panel
{
    private readonly Label dot;
    private readonly Label titleLabel;
    private readonly Label stateLabel;

    public StatusTile(string title, int x, int y, int width)
    {
        Location = new Point(x, y);
        Size = new Size(width, 56);
        BackColor = Color.FromArgb(22, 26, 36);

        dot = new Label
        {
            Size = new Size(10, 10),
            Location = new Point(14, 22),
            BackColor = Color.FromArgb(239, 68, 68),
            Text = string.Empty
        };

        titleLabel = new Label
        {
            Text = title,
            ForeColor = Color.FromArgb(148, 156, 178),
            Font = new Font("Segoe UI", 8.5f),
            Location = new Point(32, 12),
            AutoSize = true,
            BackColor = Color.Transparent
        };

        stateLabel = new Label
        {
            Text = "—",
            ForeColor = Color.FromArgb(240, 244, 255),
            Font = new Font("Segoe UI Semibold", 11f),
            Location = new Point(32, 28),
            AutoSize = true,
            BackColor = Color.Transparent
        };

        Controls.Add(dot);
        Controls.Add(titleLabel);
        Controls.Add(stateLabel);

        Paint += (s, e) =>
        {
            using (var pen = new Pen(Color.FromArgb(45, 50, 68)))
                e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var brush = new SolidBrush(dot.BackColor))
                e.Graphics.FillEllipse(brush, dot.Left, dot.Top, dot.Width, dot.Height);
        };
    }

    public void SetState(bool ok, string onText, string offText)
    {
        dot.BackColor = ok ? Color.FromArgb(16, 185, 129) : Color.FromArgb(239, 68, 68);
        stateLabel.Text = ok ? onText : offText;
        stateLabel.ForeColor = ok ? Color.FromArgb(167, 243, 208) : Color.FromArgb(254, 202, 202);
        Invalidate();
    }
}
