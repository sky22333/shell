const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const red = "\x1b[31m";
const green = "\x1b[32m";
const yellow = "\x1b[33m";
const blue = "\x1b[34m";
const nc = "\x1b[0m";

const OSInfo = struct {
    id: []const u8,
    version_id: []const u8,
};

const Context = struct {
    allocator: Allocator,
    io: Io,
};

const Cli = struct {
    out: bool = false,
    rm: bool = false,
    help: bool = false,
};

fn info(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(green ++ "[信息]" ++ nc ++ " " ++ fmt, args);
}

fn warn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(yellow ++ "[提示]" ++ nc ++ " " ++ fmt, args);
}

fn errMsg(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(red ++ "[错误]" ++ nc ++ " " ++ fmt, args);
}

fn commandOk(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn runCommand(ctx: Context, argv: []const []const u8) !void {
    const result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = argv,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    });
    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);

    if (result.stdout.len > 0) std.debug.print("{s}", .{result.stdout});
    if (result.stderr.len > 0) std.debug.print("{s}", .{result.stderr});

    if (!commandOk(result.term)) {
        return error.CommandFailed;
    }
}

fn runCommandIgnore(ctx: Context, argv: []const []const u8) void {
    runCommand(ctx, argv) catch {};
}

fn runShell(ctx: Context, script: []const u8) !void {
    try runCommand(ctx, &.{ "sh", "-c", script });
}

fn runShellIgnore(ctx: Context, script: []const u8) void {
    runShell(ctx, script) catch {};
}

fn runOutput(ctx: Context, argv: []const []const u8) ![]u8 {
    const result = try std.process.run(ctx.allocator, ctx.io, .{
        .argv = argv,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    });
    defer ctx.allocator.free(result.stderr);

    if (!commandOk(result.term)) {
        ctx.allocator.free(result.stdout);
        return error.CommandFailed;
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    const owned = try ctx.allocator.dupe(u8, trimmed);
    ctx.allocator.free(result.stdout);
    return owned;
}

fn runShellOutput(ctx: Context, script: []const u8) ![]u8 {
    return runOutput(ctx, &.{ "sh", "-c", script });
}

fn fileExists(ctx: Context, path: []const u8) bool {
    const script = std.fmt.allocPrint(ctx.allocator, "test -f '{s}'", .{path}) catch return false;
    defer ctx.allocator.free(script);
    runShell(ctx, script) catch return false;
    return true;
}

fn charDeviceExists(ctx: Context, path: []const u8) bool {
    const script = std.fmt.allocPrint(ctx.allocator, "test -c '{s}'", .{path}) catch return false;
    defer ctx.allocator.free(script);
    runShell(ctx, script) catch return false;
    return true;
}

fn dirExists(ctx: Context, path: []const u8) bool {
    const script = std.fmt.allocPrint(ctx.allocator, "test -d '{s}'", .{path}) catch return false;
    defer ctx.allocator.free(script);
    runShell(ctx, script) catch return false;
    return true;
}

fn readInput(ctx: Context, prompt: []const u8, default_value: []const u8) ![]u8 {
    std.debug.print("{s}: ", .{prompt});
    var stdin_file = std.Io.File.stdin();
    var buffer: [4096]u8 = undefined;
    var reader = stdin_file.readerStreaming(ctx.io, &buffer);
    const maybe_line = try reader.interface.takeDelimiter('\n');
    if (maybe_line) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) return try ctx.allocator.dupe(u8, default_value);
        return try ctx.allocator.dupe(u8, trimmed);
    }
    return try ctx.allocator.dupe(u8, default_value);
}

fn askYesNo(ctx: Context, prompt: []const u8) !bool {
    while (true) {
        const answer = try readInput(ctx, try std.fmt.allocPrint(ctx.allocator, "{s} [y/N]", .{prompt}), "");
        defer ctx.allocator.free(answer);
        if (std.ascii.eqlIgnoreCase(answer, "y") or std.ascii.eqlIgnoreCase(answer, "yes")) return true;
        if (answer.len == 0 or std.ascii.eqlIgnoreCase(answer, "n") or std.ascii.eqlIgnoreCase(answer, "no")) return false;
    }
}

fn randString(ctx: Context, len: usize) ![]u8 {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var out = try ctx.allocator.alloc(u8, len);
    var random_source = std.Random.IoSource{ .io = ctx.io };
    const random = random_source.interface();
    const bytes = try ctx.allocator.alloc(u8, len);
    defer ctx.allocator.free(bytes);
    random.bytes(bytes);
    for (bytes, 0..) |b, i| {
        out[i] = charset[b % charset.len];
    }
    return out;
}

fn writeFile(ctx: Context, path: []const u8, data: []const u8, mode: []const u8) !void {
    try std.Io.Dir.writeFile(.cwd(), ctx.io, .{
        .sub_path = path,
        .data = data,
        .flags = .{ .permissions = .default_file },
    });
    const chmod_cmd = try std.fmt.allocPrint(ctx.allocator, "chmod {s} '{s}'", .{ mode, path });
    defer ctx.allocator.free(chmod_cmd);
    runShellIgnore(ctx, chmod_cmd);
}

fn readFileOrEmpty(ctx: Context, path: []const u8) ![]u8 {
    return std.Io.Dir.readFileAlloc(.cwd(), ctx.io, path, ctx.allocator, .unlimited) catch |e| switch (e) {
        error.FileNotFound => try ctx.allocator.dupe(u8, ""),
        else => return e,
    };
}

fn updateConfigFile(ctx: Context, path: []const u8, keys: []const []const u8, values: []const []const u8, sep: []const u8) !void {
    const content = try readFileOrEmpty(ctx, path);
    defer ctx.allocator.free(content);

    var output = std.array_list.Managed(u8).init(ctx.allocator);
    defer output.deinit();
    var processed = try ctx.allocator.alloc(bool, keys.len);
    defer ctx.allocator.free(processed);
    @memset(processed, false);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        var updated = false;
        if (!std.mem.startsWith(u8, trimmed, "#")) {
            for (keys, 0..) |key, idx| {
                const clean_line = try removeSpaces(ctx, trimmed);
                defer ctx.allocator.free(clean_line);
                const clean_key = try removeSpaces(ctx, key);
                defer ctx.allocator.free(clean_key);
                const prefix = try std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ clean_key, std.mem.trim(u8, sep, " \t") });
                defer ctx.allocator.free(prefix);
                if (std.mem.startsWith(u8, clean_line, prefix)) {
                    try output.appendSlice(key);
                    try output.appendSlice(sep);
                    try output.appendSlice(values[idx]);
                    try output.append('\n');
                    processed[idx] = true;
                    updated = true;
                    break;
                }
            }
        }
        if (!updated and line.len > 0) {
            try output.appendSlice(line);
            try output.append('\n');
        }
    }

    for (keys, 0..) |key, idx| {
        if (!processed[idx]) {
            try output.appendSlice(key);
            try output.appendSlice(sep);
            try output.appendSlice(values[idx]);
            try output.append('\n');
        }
    }

    try writeFile(ctx, path, output.items, "0644");
}

fn removeSpaces(ctx: Context, input: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(ctx.allocator);
    errdefer out.deinit();
    for (input) |ch| {
        if (ch != ' ') try out.append(ch);
    }
    return out.toOwnedSlice();
}

fn fetchUrl(ctx: Context, url: []const u8) ![]u8 {
    const script = try std.fmt.allocPrint(
        ctx.allocator,
        "if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 5 '{s}'; elif command -v wget >/dev/null 2>&1; then wget -qO- -T 5 '{s}'; else exit 127; fi",
        .{ url, url },
    );
    defer ctx.allocator.free(script);
    return runShellOutput(ctx, script);
}

fn detectRegion(ctx: Context) bool {
    std.debug.print("{s} 检测网络位置...\n", .{blue});
    const urls = [_][]const u8{
        "https://www.cloudflare.com/cdn-cgi/trace",
        "https://www.visa.cn/cdn-cgi/trace",
    };
    for (urls) |url| {
        const body = fetchUrl(ctx, url) catch continue;
        defer ctx.allocator.free(body);
        if (std.mem.indexOf(u8, body, "loc=CN") != null) {
            std.debug.print("{s} CN 网络环境{s}\n", .{ green, nc });
            return true;
        }
    }
    std.debug.print("{s} 非 CN 网络环境{s}\n", .{ green, nc });
    return false;
}

fn changeMirrors(ctx: Context) void {
    std.debug.print("{s} [0/4] 配置软件源{s}\n", .{ yellow, nc });
    if (detectRegion(ctx)) {
        std.debug.print("使用阿里源...\n", .{});
        runShellIgnore(ctx, "bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh) --source mirrors.aliyun.com --protocol http --use-intranet-source false --install-epel true --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --pure-mode");
    } else {
        std.debug.print("使用官方源...\n", .{});
        runShellIgnore(ctx, "bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh) --use-official-source true --protocol http --use-intranet-source false --install-epel true --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --pure-mode");
    }
}

fn getOSInfo(ctx: Context) !OSInfo {
    const id = runShellOutput(ctx, ". /etc/os-release 2>/dev/null || . /usr/lib/os-release 2>/dev/null; printf '%s' \"$ID\"") catch try ctx.allocator.dupe(u8, "");
    const version = runShellOutput(ctx, ". /etc/os-release 2>/dev/null || . /usr/lib/os-release 2>/dev/null; printf '%s' \"$VERSION_ID\"") catch try ctx.allocator.dupe(u8, "");
    return .{ .id = id, .version_id = version };
}

fn checkCloudKernel(ctx: Context) bool {
    const uname = runOutput(ctx, &.{ "uname", "-r" }) catch return false;
    defer ctx.allocator.free(uname);
    return std.mem.indexOf(u8, uname, "cloud") != null;
}

fn installDependencies(ctx: Context, os_info: OSInfo) !void {
    warn("正在检查并安装依赖...\n", .{});

    var update_cmd: []const u8 = undefined;
    var install_cmd: []const u8 = undefined;

    if (std.mem.eql(u8, os_info.id, "debian") or std.mem.eql(u8, os_info.id, "ubuntu") or std.mem.eql(u8, os_info.id, "kali")) {
        update_cmd = "apt update -y -q";
        install_cmd = "apt install -y -q curl xl2tpd strongswan pptpd nftables ppp";
    } else if (std.mem.eql(u8, os_info.id, "centos") or std.mem.eql(u8, os_info.id, "almalinux") or std.mem.eql(u8, os_info.id, "rocky") or std.mem.eql(u8, os_info.id, "oracle") or std.mem.eql(u8, os_info.id, "fedora") or std.mem.eql(u8, os_info.id, "rhel")) {
        update_cmd = if (std.mem.eql(u8, os_info.id, "centos")) "yum update -y -q" else "yum update -y -q || dnf update -y -q";
        install_cmd = "yum install -y -q curl xl2tpd strongswan pptpd nftables ppp || dnf install -y -q curl xl2tpd strongswan pptpd nftables ppp";
    } else {
        return error.UnsupportedOS;
    }

    runShell(ctx, update_cmd) catch {
        warn("系统更新失败，尝试继续安装依赖...\n", .{});
    };

    try runShell(ctx, install_cmd);
}

fn getPublicIP(ctx: Context) ![]u8 {
    const apis = [_][]const u8{
        "http://api64.ipify.org",
        "http://ip.sb",
        "http://checkip.amazonaws.com",
        "http://icanhazip.com",
        "http://ipinfo.io/ip",
    };
    for (apis) |api| {
        const ip = fetchUrl(ctx, api) catch continue;
        const trimmed = std.mem.trim(u8, ip, " \t\r\n");
        if (trimmed.len > 0 and std.mem.indexOf(u8, trimmed, "<") == null) {
            const out = try ctx.allocator.dupe(u8, trimmed);
            ctx.allocator.free(ip);
            return out;
        }
        ctx.allocator.free(ip);
    }
    return try ctx.allocator.dupe(u8, "127.0.0.1");
}

fn setupSysctl(ctx: Context) !void {
    warn("正在配置 Sysctl 参数...\n", .{});
    const keys = [_][]const u8{
        "net.ipv4.ip_forward",
        "net.ipv4.conf.all.send_redirects",
        "net.ipv4.conf.default.send_redirects",
        "net.ipv4.conf.all.accept_redirects",
        "net.ipv4.conf.default.accept_redirects",
    };
    const values = [_][]const u8{ "1", "0", "0", "0", "0" };
    updateConfigFile(ctx, "/etc/sysctl.conf", &keys, &values, " = ") catch |e| {
        warn("更新 sysctl.conf 失败: {t}\n", .{e});
    };
    runCommandIgnore(ctx, &.{ "sysctl", "-p" });
}

fn setupNftables(ctx: Context, l2tp_port: []const u8, pptp_port: []const u8, l2tp_loc_ip: []const u8, pptp_loc_ip: []const u8) !void {
    if (fileExists(ctx, "/etc/nftables.conf") and !fileExists(ctx, "/etc/nftables.conf.bak")) {
        runCommandIgnore(ctx, &.{ "cp", "/etc/nftables.conf", "/etc/nftables.conf.bak" });
    }

    var interface_name = runShellOutput(ctx, "ip route get 8.8.8.8 | awk '{print $5; exit}'") catch try ctx.allocator.dupe(u8, "eth0");
    defer ctx.allocator.free(interface_name);
    if (interface_name.len == 0) {
        ctx.allocator.free(interface_name);
        interface_name = try ctx.allocator.dupe(u8, "eth0");
    }

    const config = try std.fmt.allocPrint(ctx.allocator,
        \\#!/usr/sbin/nft -f
        \\
        \\flush ruleset
        \\
        \\table inet filter {{
        \\    chain input {{
        \\        type filter hook input priority 0;
        \\        ct state established,related accept
        \\        ip protocol icmp accept
        \\        iif lo accept
        \\        udp dport {{500,4500,{s},{s}}} accept
        \\        accept
        \\    }}
        \\    chain forward {{
        \\        type filter hook forward priority 0;
        \\        ct state established,related accept
        \\        ip saddr {s}.0/24 accept
        \\        ip saddr {s}.0/24 accept
        \\        accept
        \\    }}
        \\    chain output {{
        \\        type filter hook output priority 0;
        \\        accept
        \\    }}
        \\}}
        \\
        \\table ip nat {{
        \\    chain prerouting {{
        \\        type nat hook prerouting priority 0;
        \\        accept
        \\    }}
        \\    chain postrouting {{
        \\        type nat hook postrouting priority 100;
        \\        oif "{s}" masquerade
        \\    }}
        \\    chain output {{
        \\        type nat hook output priority 0;
        \\        accept
        \\    }}
        \\}}
        \\
    , .{ l2tp_port, pptp_port, l2tp_loc_ip, pptp_loc_ip, interface_name });
    defer ctx.allocator.free(config);

    try writeFile(ctx, "/etc/nftables.conf", config, "0755");
    runCommandIgnore(ctx, &.{ "systemctl", "daemon-reload" });
    runCommandIgnore(ctx, &.{ "systemctl", "enable", "nftables" });
    try runCommand(ctx, &.{ "systemctl", "restart", "nftables" });
}

fn installVPN(ctx: Context) ![]u8 {
    const public_ip = try getPublicIP(ctx);
    defer ctx.allocator.free(public_ip);

    std.debug.print("\n", .{});
    warn("请输入 L2TP IP 范围:\n", .{});
    const l2tp_loc_ip = try readInput(ctx, "(默认范围: 10.10.10)", "10.10.10");
    errdefer ctx.allocator.free(l2tp_loc_ip);

    warn("请输入 L2TP 端口:\n", .{});
    const l2tp_port = try readInput(ctx, "(默认端口: 1701)", "1701");
    defer ctx.allocator.free(l2tp_port);

    const l2tp_user_default = try randString(ctx, 5);
    defer ctx.allocator.free(l2tp_user_default);
    warn("请输入 L2TP 用户名\n", .{});
    const l2tp_user_prompt = try std.fmt.allocPrint(ctx.allocator, "(默认用户名: {s})", .{l2tp_user_default});
    defer ctx.allocator.free(l2tp_user_prompt);
    const l2tp_user = try readInput(ctx, l2tp_user_prompt, l2tp_user_default);
    defer ctx.allocator.free(l2tp_user);

    const l2tp_pass_default = try randString(ctx, 7);
    defer ctx.allocator.free(l2tp_pass_default);
    const l2tp_pass_tip = try std.fmt.allocPrint(ctx.allocator, "请输入 {s} 的密码\n", .{l2tp_user});
    defer ctx.allocator.free(l2tp_pass_tip);
    warn("{s}", .{l2tp_pass_tip});
    const l2tp_pass_prompt = try std.fmt.allocPrint(ctx.allocator, "(默认密码: {s})", .{l2tp_pass_default});
    defer ctx.allocator.free(l2tp_pass_prompt);
    const l2tp_pass = try readInput(ctx, l2tp_pass_prompt, l2tp_pass_default);
    defer ctx.allocator.free(l2tp_pass);

    const l2tp_psk_default = try randString(ctx, 20);
    defer ctx.allocator.free(l2tp_psk_default);
    warn("请输入 L2TP PSK 密钥:\n", .{});
    const l2tp_psk_prompt = try std.fmt.allocPrint(ctx.allocator, "(默认PSK: {s})", .{l2tp_psk_default});
    defer ctx.allocator.free(l2tp_psk_prompt);
    const l2tp_psk = try readInput(ctx, l2tp_psk_prompt, l2tp_psk_default);
    defer ctx.allocator.free(l2tp_psk);

    warn("请输入 PPTP IP 范围:\n", .{});
    const pptp_loc_ip = try readInput(ctx, "(默认范围: 192.168.30)", "192.168.30");
    defer ctx.allocator.free(pptp_loc_ip);

    warn("请输入 PPTP 端口:\n", .{});
    const pptp_port = try readInput(ctx, "(默认端口: 1723)", "1723");
    defer ctx.allocator.free(pptp_port);

    const pptp_user_default = try randString(ctx, 5);
    defer ctx.allocator.free(pptp_user_default);
    warn("请输入 PPTP 用户名\n", .{});
    const pptp_user_prompt = try std.fmt.allocPrint(ctx.allocator, "(默认用户名: {s})", .{pptp_user_default});
    defer ctx.allocator.free(pptp_user_prompt);
    const pptp_user = try readInput(ctx, pptp_user_prompt, pptp_user_default);
    defer ctx.allocator.free(pptp_user);

    const pptp_pass_default = try randString(ctx, 7);
    defer ctx.allocator.free(pptp_pass_default);
    const pptp_pass_tip = try std.fmt.allocPrint(ctx.allocator, "请输入 {s} 的密码\n", .{pptp_user});
    defer ctx.allocator.free(pptp_pass_tip);
    warn("{s}", .{pptp_pass_tip});
    const pptp_pass_prompt = try std.fmt.allocPrint(ctx.allocator, "(默认密码: {s})", .{pptp_pass_default});
    defer ctx.allocator.free(pptp_pass_prompt);
    const pptp_pass = try readInput(ctx, pptp_pass_prompt, pptp_pass_default);
    defer ctx.allocator.free(pptp_pass);

    std.debug.print("\n", .{});
    info("L2TP服务器本地IP: {s}{s}.1{s}\n", .{ green, l2tp_loc_ip, nc });
    info("L2TP客户端IP范围: {s}{s}.11-{s}.255{s}\n", .{ green, l2tp_loc_ip, l2tp_loc_ip, nc });
    info("L2TP端口    : {s}{s}{s}\n", .{ green, l2tp_port, nc });
    info("L2TP用户名  : {s}{s}{s}\n", .{ green, l2tp_user, nc });
    info("L2TP密码    : {s}{s}{s}\n", .{ green, l2tp_pass, nc });
    info("L2TP PSK密钥: {s}{s}{s}\n", .{ green, l2tp_psk, nc });
    std.debug.print("\n", .{});
    info("PPTP服务器本地IP: {s}{s}.1{s}\n", .{ green, pptp_loc_ip, nc });
    info("PPTP客户端IP范围: {s}{s}.11-{s}.255{s}\n", .{ green, pptp_loc_ip, pptp_loc_ip, nc });
    info("PPTP端口    : {s}{s}{s}\n", .{ green, pptp_port, nc });
    info("PPTP用户名  : {s}{s}{s}\n", .{ green, pptp_user, nc });
    info("PPTP密码    : {s}{s}{s}\n", .{ green, pptp_pass, nc });
    std.debug.print("\n正在生成配置文件...\n", .{});

    const ipsec_conf = try std.fmt.allocPrint(ctx.allocator,
        \\config setup
        \\    charondebug="ike 2, knl 2, cfg 2"
        \\    uniqueids=no
        \\
        \\conn %default
        \\    keyexchange=ikev1
        \\    authby=secret
        \\    ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
        \\    esp=aes256-sha1,aes128-sha1,3des-sha1!
        \\    keyingtries=3
        \\    ikelifetime=8h
        \\    lifetime=1h
        \\    dpdaction=clear
        \\    dpddelay=30s
        \\    dpdtimeout=120s
        \\    rekey=no
        \\    forceencaps=yes
        \\    fragmentation=yes
        \\
        \\conn L2TP-PSK
        \\    left=%any
        \\    leftid={s}
        \\    leftfirewall=yes
        \\    leftprotoport=17/{s}
        \\    right=%any
        \\    rightprotoport=17/%any
        \\    type=transport
        \\    auto=add
        \\    also=%default
        \\
    , .{ public_ip, l2tp_port });
    defer ctx.allocator.free(ipsec_conf);
    try writeFile(ctx, "/etc/ipsec.conf", ipsec_conf, "0644");

    const ipsec_secrets = try std.fmt.allocPrint(ctx.allocator, "%any %any : PSK \"{s}\"\n", .{l2tp_psk});
    defer ctx.allocator.free(ipsec_secrets);
    try writeFile(ctx, "/etc/ipsec.secrets", ipsec_secrets, "0600");

    try runCommand(ctx, &.{ "mkdir", "-p", "/etc/xl2tpd" });
    const xl2tpd_conf = try std.fmt.allocPrint(ctx.allocator,
        \\[global]
        \\port = {s}
        \\
        \\[lns default]
        \\ip range = {s}.11-{s}.255
        \\local ip = {s}.1
        \\require chap = yes
        \\refuse pap = yes
        \\require authentication = yes
        \\name = l2tpd
        \\ppp debug = yes
        \\pppoptfile = /etc/ppp/options.xl2tpd
        \\length bit = yes
        \\
    , .{ l2tp_port, l2tp_loc_ip, l2tp_loc_ip, l2tp_loc_ip });
    defer ctx.allocator.free(xl2tpd_conf);
    try writeFile(ctx, "/etc/xl2tpd/xl2tpd.conf", xl2tpd_conf, "0644");

    try runCommand(ctx, &.{ "mkdir", "-p", "/etc/ppp" });
    const ppp_opt_xl2tpd =
        \\ipcp-accept-local
        \\ipcp-accept-remote
        \\require-mschap-v2
        \\noccp
        \\auth
        \\hide-password
        \\idle 1800
        \\mtu 1410
        \\mru 1410
        \\nodefaultroute
        \\debug
        \\proxyarp
        \\connect-delay 5000
        \\
    ;
    try writeFile(ctx, "/etc/ppp/options.xl2tpd", ppp_opt_xl2tpd, "0644");

    const pptpd_conf = try std.fmt.allocPrint(ctx.allocator,
        \\option /etc/ppp/pptpd-options
        \\debug
        \\localip {s}.1
        \\remoteip {s}.11-255
        \\
    , .{ pptp_loc_ip, pptp_loc_ip });
    defer ctx.allocator.free(pptpd_conf);
    try writeFile(ctx, "/etc/pptpd.conf", pptpd_conf, "0644");

    const pptpd_options =
        \\name pptpd
        \\refuse-pap
        \\refuse-chap
        \\refuse-mschap
        \\require-mschap-v2
        \\require-mppe-128
        \\proxyarp
        \\lock
        \\nobsdcomp
        \\novj
        \\novjccomp
        \\nologfd
        \\
    ;
    try writeFile(ctx, "/etc/ppp/pptpd-options", pptpd_options, "0644");

    var chap = std.array_list.Managed(u8).init(ctx.allocator);
    defer chap.deinit();
    try chap.appendSlice("# Secrets for authentication using CHAP\n# client    server    secret    IP addresses\n");
    try chap.print("{s}    l2tpd    {s}    {s}.10\n", .{ l2tp_user, l2tp_pass, l2tp_loc_ip });
    try chap.print("{s}    pptpd    {s}    {s}.10\n", .{ pptp_user, pptp_pass, pptp_loc_ip });
    var i: usize = 11;
    while (i <= 255) : (i += 1) {
        try chap.print("{s}{d}    l2tpd    {s}{d}    {s}.{d}\n", .{ l2tp_user, i, l2tp_pass, i, l2tp_loc_ip, i });
        try chap.print("{s}{d}    pptpd    {s}{d}    {s}.{d}\n", .{ pptp_user, i, pptp_pass, i, pptp_loc_ip, i });
    }
    try writeFile(ctx, "/etc/ppp/chap-secrets", chap.items, "0600");

    try setupSysctl(ctx);
    try setupNftables(ctx, l2tp_port, pptp_port, l2tp_loc_ip, pptp_loc_ip);

    std.debug.print("正在启动服务...\n", .{});
    var ipsec_service: []const u8 = "ipsec";
    if (runCommand(ctx, &.{ "systemctl", "list-unit-files", "strongswan.service" })) |_| {
        if (runCommand(ctx, &.{ "systemctl", "list-unit-files", "ipsec.service" })) |_| {} else |_| {
            ipsec_service = "strongswan";
        }
    } else |_| {}

    runCommandIgnore(ctx, &.{ "systemctl", "daemon-reload" });
    writeFile(ctx, "/proc/sys/net/ipv4/ip_forward", "1\n", "0644") catch |e| {
        warn("无法写入 ip_forward: {t}\n", .{e});
    };

    try runCommand(ctx, &.{ "systemctl", "enable", ipsec_service });
    try runCommand(ctx, &.{ "systemctl", "restart", ipsec_service });
    try runCommand(ctx, &.{ "systemctl", "enable", "xl2tpd" });
    try runCommand(ctx, &.{ "systemctl", "restart", "xl2tpd" });
    try runCommand(ctx, &.{ "systemctl", "enable", "pptpd" });
    try runCommand(ctx, &.{ "systemctl", "restart", "pptpd" });

    std.debug.print("\n{s}==============================================={s}\n", .{ green, nc });
    std.debug.print("{s}VPN 安装完成{s}\n", .{ green, nc });
    std.debug.print("{s}==============================================={s}\n", .{ green, nc });
    std.debug.print("请保留好以下信息:\n", .{});
    std.debug.print("服务器IP: {s}\n", .{public_ip});
    std.debug.print("L2TP PSK: {s}\n", .{l2tp_psk});
    std.debug.print("L2TP 主账号: {s} / 密码: {s}\n", .{ l2tp_user, l2tp_pass });
    std.debug.print("PPTP 主账号: {s} / 密码: {s}\n", .{ pptp_user, pptp_pass });
    std.debug.print("\n{s} 已自动生成批量账号，详情请查看 /etc/ppp/chap-secrets 文件{s}\n", .{ yellow, nc });

    return l2tp_loc_ip;
}

fn configureSingboxFirewall(ctx: Context, l2tp_loc_ip: []const u8, port: []const u8) !void {
    warn("配置透明代理分流规则 (端口: {s})...\n", .{port});

    runCommandIgnore(ctx, &.{ "/bin/ip", "rule", "add", "fwmark", "1", "table", "100" });
    runCommandIgnore(ctx, &.{ "/bin/ip", "route", "add", "local", "0.0.0.0/0", "dev", "lo", "table", "100" });
    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-N", "SINGBOX" });

    const private_ips = [_][]const u8{
        "0.0.0.0/8",
        "10.0.0.0/8",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "224.0.0.0/4",
        "240.0.0.0/4",
    };
    for (private_ips) |ip| {
        runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-A", "SINGBOX", "-d", ip, "-j", "RETURN" });
    }

    const subnet = try std.fmt.allocPrint(ctx.allocator, "{s}.0/24", .{l2tp_loc_ip});
    defer ctx.allocator.free(subnet);
    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-A", "SINGBOX", "-s", subnet, "-p", "tcp", "-j", "TPROXY", "--on-port", port, "--tproxy-mark", "1" });
    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-A", "SINGBOX", "-s", subnet, "-p", "udp", "-j", "TPROXY", "--on-port", port, "--tproxy-mark", "1" });
    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-A", "PREROUTING", "-j", "SINGBOX" });
    runCommandIgnore(ctx, &.{ "iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "DROP" });
    runCommandIgnore(ctx, &.{ "iptables", "-I", "INPUT", "-p", "udp", "--dport", port, "-j", "DROP" });

    std.debug.print("{s} 透明代理分流规则配置完成{s}\n", .{ green, nc });
}

fn uninstallService(ctx: Context, port: []const u8, os_info: OSInfo) void {
    warn("正在卸载服务...\n", .{});

    runShellIgnore(ctx, "systemctl stop xl2tpd strongswan-starter strongswan ipsec pptpd 2>/dev/null || true");
    runShellIgnore(ctx, "systemctl disable xl2tpd strongswan-starter strongswan ipsec pptpd 2>/dev/null || true");

    if (std.mem.eql(u8, os_info.id, "debian") or std.mem.eql(u8, os_info.id, "ubuntu") or std.mem.eql(u8, os_info.id, "kali")) {
        runShellIgnore(ctx, "apt purge -y xl2tpd strongswan pptpd");
    } else {
        runShellIgnore(ctx, "yum remove -y xl2tpd strongswan pptpd || dnf remove -y xl2tpd strongswan pptpd");
    }

    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-D", "PREROUTING", "-j", "SINGBOX" });
    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-F", "SINGBOX" });
    runCommandIgnore(ctx, &.{ "iptables", "-t", "mangle", "-X", "SINGBOX" });
    runCommandIgnore(ctx, &.{ "/bin/ip", "route", "del", "local", "0.0.0.0/0", "dev", "lo", "table", "100" });
    runCommandIgnore(ctx, &.{ "/bin/ip", "rule", "del", "fwmark", "1", "table", "100" });
    runCommandIgnore(ctx, &.{ "iptables", "-D", "INPUT", "-p", "tcp", "--dport", port, "-j", "DROP" });
    runCommandIgnore(ctx, &.{ "iptables", "-D", "INPUT", "-p", "udp", "--dport", port, "-j", "DROP" });

    std.debug.print("{s} 卸载完成{s}\n", .{ green, nc });
}

fn parseCli(ctx: Context, args_source: std.process.Args) !Cli {
    var cli = Cli{};
    var it = try std.process.Args.Iterator.initAllocator(args_source, ctx.allocator);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-out") or std.mem.eql(u8, arg, "--out")) {
            cli.out = true;
        } else if (std.mem.eql(u8, arg, "-rm") or std.mem.eql(u8, arg, "--rm")) {
            cli.rm = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            cli.help = true;
        } else {
            errMsg("未知参数: {s}\n", .{arg});
            cli.help = true;
        }
    }
    return cli;
}

fn printHelp() void {
    std.debug.print(
        \\用法:
        \\  l2tp.zig [-out] [-rm]
        \\
        \\参数:
        \\  -out, --out   安装完成后配置透明代理分流规则
        \\  -rm,  --rm    卸载服务并清理分流规则
        \\  -h,   --help  显示帮助
        \\
    , .{});
}

fn ensureRoot(ctx: Context) !void {
    const uid = runShellOutput(ctx, "id -u") catch return error.NotRoot;
    defer ctx.allocator.free(uid);
    if (!std.mem.eql(u8, uid, "0")) return error.NotRoot;
}

pub fn main(init: std.process.Init) !void {
    const ctx = Context{
        .allocator = init.gpa,
        .io = init.io,
    };

    const cli = try parseCli(ctx, init.minimal.args);
    if (cli.help) {
        printHelp();
        return;
    }

    ensureRoot(ctx) catch {
        errMsg("必须使用 root 权限运行此脚本\n", .{});
        return;
    };

    const os_info = try getOSInfo(ctx);
    defer ctx.allocator.free(os_info.id);
    defer ctx.allocator.free(os_info.version_id);

    if (cli.rm) {
        warn("请输入配置时使用的透明代理分流端口:\n", .{});
        const port = try readInput(ctx, "(默认: 12345)", "12345");
        defer ctx.allocator.free(port);
        uninstallService(ctx, port, os_info);
        return;
    }

    std.debug.print("\x1b[H\x1b[2J", .{});
    std.debug.print("{s}###############################################################{s}\n", .{ green, nc });
    std.debug.print("{s}# L2TP/IPSec & PPTP VPN 一键安装脚本                         #{s}\n", .{ green, nc });
    std.debug.print("{s}###############################################################{s}\n\n", .{ green, nc });

    if (dirExists(ctx, "/proc/vz")) {
        errMsg("你的 VPS 基于 OpenVZ，内核可能不支持 IPSec，L2TP 安装已取消\n", .{});
        return;
    }

    runCommandIgnore(ctx, &.{ "modprobe", "ppp_generic" });
    
    if (!charDeviceExists(ctx, "/dev/ppp")) {
        errMsg("未检测到 /dev/ppp 字符设备，当前内核可能不支持 PPP，无法继续安装 VPN\n", .{});
        return;
    }

    if (checkCloudKernel(ctx)) {
        warn("检测到当前运行在 Cloud 内核上，脚本将退出；请先手动切换到支持 PPP/IPSec 的标准内核后再运行。\n", .{});
        return;
    }

    changeMirrors(ctx);
    installDependencies(ctx, os_info) catch |e| {
        errMsg("依赖安装失败: {t}\n", .{e});
        return;
    };

    const l2tp_loc_ip = installVPN(ctx) catch |e| {
        errMsg("VPN 安装失败: {t}\n", .{e});
        return;
    };
    defer ctx.allocator.free(l2tp_loc_ip);

    if (cli.out) {
        warn("请输入透明代理分流端口:\n", .{});
        const port = try readInput(ctx, "(默认: 12345)", "12345");
        defer ctx.allocator.free(port);
        configureSingboxFirewall(ctx, l2tp_loc_ip, port) catch |e| {
            errMsg("透明代理分流配置失败: {t}\n", .{e});
        };
    }
}
