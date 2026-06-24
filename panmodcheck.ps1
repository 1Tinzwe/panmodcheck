#Requires -Version 5.1
# ===============================================================================
#   PANN MOD CHECK  v2.0  |  Minecraft Cheat Mod Detector
#   6 Scan Passes · Risk Scoring · Entropy Analysis · Network Detection
# ===============================================================================

Set-StrictMode -Off

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
try { $Host.UI.RawUI.WindowTitle = "Pann Mod Check  v2.0" } catch {}
Clear-Host

# ═══════════════════════════════════════════════════════════════════════════════
#  TIMING SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

$script:T0      = Get-Date
$script:PassLog = [System.Collections.Specialized.OrderedDictionary]::new()
$script:CurPass = $null

function Start-Pass ([string]$Name) {
    $script:CurPass     = $Name
    $script:PassLog[$Name] = @{ S = Get-Date; E = $null; I = 0; Extra = "" }
}

function Stop-Pass ([int]$Issues = 0, [string]$Extra = "") {
    if ($script:CurPass) {
        $script:PassLog[$script:CurPass].E     = Get-Date
        $script:PassLog[$script:CurPass].I     = $Issues
        $script:PassLog[$script:CurPass].Extra = $Extra
    }
}

function Fmt-Ms ([double]$ms) {
    if ($ms -lt 100)   { return ("{0}ms"   -f [math]::Round($ms)) }
    if ($ms -lt 1000)  { return ("{0}ms"   -f [math]::Round($ms)) }
    if ($ms -lt 60000) { return ("{0:F2}s" -f ($ms / 1000)) }
    $m = [math]::Floor($ms / 60000)
    $s = [math]::Round(($ms % 60000) / 1000)
    return ("{0}m {1}s" -f $m, $s)
}

function Fmt-Span ([datetime]$A, [datetime]$B) {
    Fmt-Ms (([datetime]$B - [datetime]$A).TotalMilliseconds)
}

function Get-TotalElapsed { Fmt-Span $script:T0 (Get-Date) }

# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

$COL = 78

function Blank  { Write-Host "" }

function Rule {
    param([string]$Char = "─", [ConsoleColor]$Fg = "DarkGray")
    Write-Host ("  " + ($Char * ($COL - 2))) -ForegroundColor $Fg
}

function ProgressBar {
    param([int]$Cur, [int]$Tot, [string]$Label = "", [ConsoleColor]$BC = "Cyan")
    $bw  = 28
    $n   = if ($Tot -gt 0) { [math]::Min($bw, [math]::Round(($Cur / $Tot) * $bw)) } else { 0 }
    $pct = if ($Tot -gt 0) { [math]::Round(($Cur / $Tot) * 100) } else { 0 }
    $lbl = if ($Label.Length -gt 35) { $Label.Substring(0,32) + "..." } else { $Label.PadRight(35) }
    Write-Host "`r  [" -NoNewline -ForegroundColor DarkGray
    Write-Host ("█" * $n + "░" * ($bw - $n)) -NoNewline -ForegroundColor $BC
    Write-Host "]" -NoNewline -ForegroundColor DarkGray
    Write-Host (" {0,3}%  " -f $pct) -NoNewline -ForegroundColor White
    Write-Host $lbl -NoNewline -ForegroundColor DarkGray
}

function ClearLine { Write-Host ("`r" + (" " * ($COL + 6)) + "`r") -NoNewline }

function PassDone {
    param([string]$Name, [string]$Dur, [int]$Issues, [string]$Extra = "")
    ClearLine
    Write-Host "  ├─ " -ForegroundColor DarkCyan -NoNewline
    Write-Host ($Name.PadRight(30)) -ForegroundColor White -NoNewline
    if ($Issues -gt 0) {
        Write-Host ("⚠  " + ("$Issues flagged").PadRight(15)) -ForegroundColor Yellow -NoNewline
    } else {
        Write-Host ("✓  " + "clean".PadRight(15)) -ForegroundColor DarkGray -NoNewline
    }
    Write-Host "[$Dur]" -ForegroundColor DarkGray
    if ($Extra) { Write-Host "  │     $Extra" -ForegroundColor DarkGray }
}

function SectHeader {
    param([string]$Icon, [string]$Title, [int]$Count, [ConsoleColor]$Accent)
    Blank
    Rule "─" DarkGray
    Write-Host "  $Icon " -ForegroundColor $Accent -NoNewline
    Write-Host $Title -ForegroundColor White -NoNewline
    Write-Host "  ($Count)" -ForegroundColor $Accent
    Rule "─" DarkGray
    Blank
}

function RiskBadge {
    param([int]$Score)
    if ($Score -ge 75) {
        Write-Host " CRITICAL " -ForegroundColor White -BackgroundColor DarkRed -NoNewline
        Write-Host "  Risk: $Score / 100" -ForegroundColor Red
    } elseif ($Score -ge 50) {
        Write-Host "  HIGH    " -ForegroundColor White -BackgroundColor DarkMagenta -NoNewline
        Write-Host "  Risk: $Score / 100" -ForegroundColor Magenta
    } elseif ($Score -ge 25) {
        Write-Host "  MEDIUM  " -ForegroundColor Black -BackgroundColor DarkYellow -NoNewline
        Write-Host "  Risk: $Score / 100" -ForegroundColor Yellow
    } else {
        Write-Host "  LOW     " -ForegroundColor White -BackgroundColor DarkBlue -NoNewline
        Write-Host "  Risk: $Score / 100" -ForegroundColor Blue
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  BANNER
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host @"

  ██████╗  █████╗ ███╗   ██╗███╗   ██╗
  ██╔══██╗██╔══██╗████╗  ██║████╗  ██║
  ██████╔╝███████║██╔██╗ ██║██╔██╗ ██║
  ██╔═══╝ ██╔══██║██║╚██╗██║██║╚██╗██║
  ██║     ██║  ██║██║ ╚████║██║ ╚████║
  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝
"@ -ForegroundColor Blue

Write-Host @"
  ███╗   ███╗ ██████╗ ██████╗     ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗
  ████╗ ████║██╔═══██╗██╔══██╗   ██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝
  ██╔████╔██║██║   ██║██║  ██║   ██║     ███████║█████╗  ██║     █████╔╝ 
  ██║╚██╔╝██║██║   ██║██║  ██║   ██║     ██╔══██║██╔══╝  ██║     ██╔═██╗ 
  ██║ ╚═╝ ██║╚██████╔╝██████╔╝   ╚██████╗██║  ██║███████╗╚██████╗██║  ██╗
  ╚═╝     ╚═╝ ╚═════╝ ╚═════╝     ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝
"@ -ForegroundColor Cyan

Blank
$box1 = "─" * 74
Write-Host "  ┌$box1┐" -ForegroundColor DarkCyan
Write-Host "  │  " -ForegroundColor DarkCyan -NoNewline
Write-Host "v2.0" -ForegroundColor Cyan -NoNewline
Write-Host "  ·  6 Scan Passes  ·  Risk Scoring  ·  Entropy  ·  Network Detection" -ForegroundColor DarkGray -NoNewline
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  └$box1┘" -ForegroundColor DarkCyan
Blank

# ═══════════════════════════════════════════════════════════════════════════════
#  PATH INPUT
# ═══════════════════════════════════════════════════════════════════════════════

Rule "─" DarkCyan
Write-Host "  📂  " -NoNewline
Write-Host "Mods Folder" -ForegroundColor White -NoNewline
Write-Host "  (press Enter for default)" -ForegroundColor DarkGray
Rule "─" DarkCyan
Blank
Write-Host "  PATH  " -ForegroundColor DarkCyan -NoNewline
$modsPath = Read-Host

if ([string]::IsNullOrWhiteSpace($modsPath)) {
    $modsPath = "$env:USERPROFILE\AppData\Roaming\.minecraft\mods"
}
$modsPath = $modsPath.Trim('"').Trim("'")

Blank
if (-not (Test-Path $modsPath -PathType Container)) {
    Write-Host "  ✗  Path not found or not accessible:" -ForegroundColor Red
    Write-Host "     $modsPath" -ForegroundColor DarkGray
    Blank
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "  ✓  " -ForegroundColor Green -NoNewline
Write-Host $modsPath -ForegroundColor White
Blank

# ═══════════════════════════════════════════════════════════════════════════════
#  MINECRAFT PROCESS DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

$mcProc = Get-Process javaw -ErrorAction SilentlyContinue
if (-not $mcProc) { $mcProc = Get-Process java -ErrorAction SilentlyContinue }

if ($mcProc) {
    $mc = $mcProc | Select-Object -First 1
    try {
        $up = (Get-Date) - $mc.StartTime
        Rule "─" DarkGray
        Write-Host "  🕒  " -NoNewline
        Write-Host "Minecraft is running" -ForegroundColor Yellow -NoNewline
        Write-Host "  PID $($mc.Id)  ·  started " -ForegroundColor DarkGray -NoNewline
        Write-Host $mc.StartTime.ToString("HH:mm:ss") -ForegroundColor White -NoNewline
        Write-Host "  ·  uptime " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0}h {1}m {2}s" -f $up.Hours, $up.Minutes, $up.Seconds) -ForegroundColor White
        Rule "─" DarkGray
        Blank
    } catch {}
}

# ═══════════════════════════════════════════════════════════════════════════════
#  JAR INVENTORY
# ═══════════════════════════════════════════════════════════════════════════════

try {
    $jarFiles = Get-ChildItem -Path $modsPath -Filter *.jar -ErrorAction Stop
} catch {
    Write-Host "  ✗  Cannot read directory: $_" -ForegroundColor Red
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); exit 1
}

if ($jarFiles.Count -eq 0) {
    Write-Host "  ⚠  No JAR files found." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); exit 0
}

$scanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "  Found " -ForegroundColor DarkGray -NoNewline
Write-Host "$($jarFiles.Count)" -ForegroundColor White -NoNewline
Write-Host " JAR file(s)  ·  $scanDate" -ForegroundColor DarkGray
Blank

# ═══════════════════════════════════════════════════════════════════════════════
#  PATTERN DATABASES
# ═══════════════════════════════════════════════════════════════════════════════

Add-Type -AssemblyName System.IO.Compression.FileSystem

$suspiciousPatterns = @(
    "AimAssist","AnchorTweaks","AutoAnchor","AutoCrystal","AutoDoubleHand",
    "JDWP.VirtualMachine.AllModules","AutoHitCrystal","AutoPot","AutoTotem",
    "AutoArmor","InventoryTotem","LegitTotem","PingSpoof","SelfDestruct",
    "ShieldBreaker","TriggerBot","AxeSpam","WebMacro","FastPlace",
    "WalskyOptimizer","WalksyOptimizer","walsky.optimizer","WalksyCrystalOptimizerMod",
    "Donut","Replace Mod","ShieldDisabler","SilentAim","Totem Hit","Wtap",
    "FakeLag","BlockESP","dev.krypton","dev/krypton","skid.krypton","skid/krypton",
    "AntiMissClick","LagReach","PopSwitch","SprintReset","ChestSteal","AntiBot",
    "ElytraSwap","FastXP","FastExp","Refill","AirAnchor","jnativehook",
    "FakeInv","HoverTotem","AutoClicker","AutoFirework","PackSpoof",
    "Antiknockback","catlean","AuthBypass","Asteria","Prestige","AutoEat",
    "AutoMine","MaceSwap","Macro198","StunSlam","SafeAnchor","DoubleAnchor",
    "AutoTPA","BaseFinder","Xenon","gypsy","AutoPotRefill","KeyPearl",
    "AutoNethPot","AutoDtap","AutoWeb","AnchorAction",
    "org.chainlibs.module.impl.modules.Crystal.Y",
    "org.chainlibs.module.impl.modules.Crystal.bF",
    "org.chainlibs.module.impl.modules.Crystal.bM",
    "org.chainlibs.module.impl.modules.Crystal.bY",
    "org.chainlibs.module.impl.modules.Crystal.bq",
    "org.chainlibs.module.impl.modules.Crystal.cv",
    "org.chainlibs.module.impl.modules.Crystal.o",
    "org.chainlibs.module.impl.modules.Blatant.I",
    "org.chainlibs.module.impl.modules.Blatant.bR",
    "org.chainlibs.module.impl.modules.Blatant.bx",
    "org.chainlibs.module.impl.modules.Blatant.cj",
    "org.chainlibs.module.impl.modules.Blatant.dk",
    "imgui.gl3","imgui.glfw","BowAim","Criticals","Fakenick","FakeItem",
    "invsee","ItemExploit","Hellion","hellion","LicenseCheckMixin",
    "ClientPlayerInteractionManagerAccessor","ClientPlayerEntityMixim",
    "dev.gambleclient","obfuscatedAuth","phantom-refmap.json","xyz.greaj",
    "じ.class","ふ.class","ぶ.class","ぷ.class","た.class","ね.class",
    "そ.class","な.class","ど.class","ぐ.class","ず.class","で.class",
    "つ.class","べ.class","せ.class","と.class","み.class","び.class",
    "す.class","の.class",
    # Extra patterns (v2 additions)
    "CorruptClient","AbsoluteClient","EclipseClient","FlareClient",
    "SigmaClient","HolyWar","StormClient","BypassMod","HackClient",
    "GodMode","NoClip","FreeCam","KillAura","CrystalAura",
    "BedAura","AntiCheatBypass","GrimBypass","VulcanBypass"
)

$cheatStrings = @(
    "AutoCrystal","autocrystal","auto crystal","cw crystal","JDWP.VirtualMachine.AllModules",
    "dontPlaceCrystal","dontBreakCrystal","AutoHitCrystal","autohitcrystal",
    "canPlaceCrystalServer","healPotSlot",
    "ＡｕｔｏＣｒｙｓｔａｌ","Ａｕｔｏ Ｃｒｙｓｔａｌ","ＡｕｔｏＨｉｔＣｒｙｓｔａｌ",
    "AutoAnchor","autoanchor","auto anchor","DoubleAnchor","HasAnchor",
    "anchortweaks","anchor macro","safe anchor","safeanchor","SafeAnchor","AirAnchor",
    "ＡｕｔｏＡｎｃｈｏｒ","Ａｕｔｏ Ａｎｃｈｏｒ","ＤｏｕｂｌｅＡｎｃｈｏｒ",
    "ＳａｆｅＡｎｃｈｏｒ","Ａｎｃｈｏｒ Ｍａｃｒｏ","anchorMacro",
    "AutoTotem","autototem","auto totem","InventoryTotem","inventorytotem",
    "HoverTotem","hover totem","legittotem",
    "ＡｕｔｏＴｏｔｅｍ","Ａｕｔｏ Ｔｏｔｅｍ","ＨｏｖｅｒＴｏｔｅｍ",
    "ＩｎｖｅｎｔｏｒｙＴｏｔｅｍ","Ａｕｔｏ Ｉｎｖｅｎｔｏｒｙ Ｔｏｔｅｍ",
    "AutoPot","autopot","auto pot","speedPotSlot","strengthPotSlot",
    "AutoArmor","autoarmor","auto armor",
    "ＡｕｔｏＰｏｔ","Ａｕｔｏ Ｐｏｔ","Ａｕｔｏ Ｐｏｔ Ｒｅｆｉｌｌ","AutoPotRefill",
    "ＡｕｔｏＡｒｍｏｒ",
    "preventSwordBlockBreaking","preventSwordBlockAttack","ShieldDisabler","ShieldBreaker",
    "ＳｈｉｅｌｄＤｉｓａｂｌｅｒ","Breaking shield with axe...",
    "AutoDoubleHand","autodoublehand","ＡｕｔｏＤｏｕｂｌｅＨａｎｄ",
    "AutoClicker","ＡｕｔｏＣｌｉｃｋｅｒ",
    "Failed to switch to mace after axe!","AutoMace","MaceSwap","SpearSwap",
    "ＡｕｔｏＭａｃｅ","ＭａｃｅＳｗａｐ","Ｓｔｕｎ Ｓｌａｍ","StunSlam",
    "Donut","JumpReset","axespam","axe spam","findKnockbackSword","attackRegisteredThisClick",
    "AimAssist","aimassist","aim assist","triggerbot","trigger bot",
    "ＡｉｍＡｓｓｉｓｔ","ＴｒｉｇｇｅｒＢｏｔ",
    "Silent Rotations","SilentRotations","Ｓｉｌｅｎｔ Ｒｏｔａｔｉｏｎｓ",
    "FakeInv","swapBackToOriginalSlot","FakeLag","pingspoof","ping spoof",
    "ＦａｋｅＬａｇ","fakePunch","Fake Punch","Ｆａｋｅ Ｐｕｎｃｈ",
    "mace_swap","quick_strike","macro_198","stun_slam","safe_anchor","double_anchor",
    "auto_pot_refill","walksy_optimizer","key_pearl","aim_assist","auto_neth_pot",
    "auto_dtap","trigger_bot","auto_web",
    "DOUBLE_ESCAPE","DOUBLE_RIGHTCLICK_FIRST","DOUBLE_RIGHTCLICK_SECOND",
    "POST_CYCLE_DELAY","PLACE_OBI","WAIT_OBI","PLACE_CRYSTAL","BREAK_CRYSTAL",
    "ROTATING_DOWN","ROTATING_BACK","REFILLING","PLANTING","BONEMEALING",
    "AnchorAction","Places two anchors for massive damage","REOFFHAND_TOTEM",
    "webmacro","web macro","AntiWeb","AutoWeb","Ａｎｔｉ Ｗｅｂ","ＡｕｔｏＷｅｂ",
    "lvstrng","dqrkis","selfdestruct","self destruct",
    "WalksyCrystalOptimizerMod","WalksyOptimizer","WalskyOptimizer",
    "Ｗａｌｋｓｙ Ｏｐｔｉｍｉｚｅｒ","autoCrystalPlaceClock",
    "AutoFirework","ElytraSwap","FastXP","FastExp","NoJumpDelay",
    "ＥｌｙｔｒａＳｗａｐ","PackSpoof","Antiknockback","catlean",
    "AuthBypass","obfuscatedAuth","LicenseCheckMixin","BaseFinder","invsee","ItemExploit",
    "FreezePlayer","Ｆｒｅｅｃａｍ","Ｍｏｖｅ ｆｒｅｅｌｙ ｔｈｒｏｕｇｈ ｗａｌｌｓ",
    "Ｎｏ Ｃｌｉｐ","LWFH Crystal","ＬＷＦＨ Ｃｒｙｓｔａｌ",
    "KeyPearl","LootYeeter","ＫｅｙＰｅａｒｌ","Ｌｏｏｔ Ｙｅｅｔｅｒ",
    "FastPlace","Ｆａｓｔ Ｐｌａｃｅ","setBlockBreakingCooldown","getBlockBreakingCooldown",
    "blockBreakingCooldown","onBlockBreaking","setItemUseCooldown",
    "invokeDoAttack","invokeDoItemUse","invokeOnMouseButton",
    "onPushOutOfBlocks","onIsGlowing","arrayOfString","POT_CHEATS",
    "Dqrkis Client","Entity.isGlowing","Activate Key","Click Simulation","On RMB",
    "No Count Glitch","No Bounce","NoBounce","Ｎｏ Ｂｏｕｎｃｅ",
    "Ｒｅｍｏｖｅｓ ｔｈｅ ｃｒｙｓｔａｌ ｂｏｕｎｃｅ ａｎｉｍａｔｉｏｎ",
    "Place Delay","Break Delay","Place Chance","Break Chance","Stop On Kill",
    "Ｄａｍａｇｅ Ｔｉｃｋ","damagetick","Anti Weakness","Particle Chance",
    "Trigger Key","Switch Delay","Totem Slot","Silent Rotations","Smooth Rotations",
    "Rotation Speed","Use Easing","Easing Strength","While Use","Stop on Kill",
    "Glowstone Delay","Glowstone Chance","Explode Delay","Explode Chance","Explode Slot",
    "Only Charge","Anchor Macro","Reach Distance","Min Height","Min Fall Speed",
    "Attack Delay","Breach Delay","Require Elytra","Auto Switch Back",
    "Check Line of Sight","Only When Falling","Require Crit","Show Status Display",
    "Stop On Crystal","Check Shield","On Pop","Predict Damage","On Ground",
    "Check Players","Predict Crystals","Check Aim","Check Items","Activates Above",
    "Blatant","Ｂｌａｔａｎｔ","Force Totem","Stay Open For","Auto Inventory Totem",
    "Only On Pop","Vertical Speed","Hover Totem","Swap Speed","Strict One-Tick",
    "Mace Priority","Min Totems","Min Pearls","Totem First","Drop Interval",
    "Random Pattern","Loot Yeeter","Horizontal Aim Speed","Vertical Aim Speed",
    "Include Head","Web Delay","Holding Web","Not When Affects Player","Hit Delay",
    "Require Hold Axe","Fake Punch","placeInterval","breakInterval","stopOnKill",
    "activateOnRightClick","holdCrystal","ｄａｍａｇｅｔｉｃｋ","ｈｏｌｄＣｒｙｓｔａｌ",
    "Ｒｅｆｉｌｌｓ ｙｏｕｒ ｈｏｔｂａｒ ｗｉｔｈ ｐｏｔｉｏｎｓ",
    "Ｐｌａｃｅｓ ａｎｃｈｏｒ， ｃｈａｒｇｅｓ ｉｔ，",
    "Ａｕｔｏ ｓｗａｐ ｔｏ ｓｐｅａｒ ｏｎ ａｔｔａｃｋ",
    "KillAura","ClickAura","MultiAura","ForceField","LegitAura","AimBot","AutoAim",
    "SilentAim","AimLock","HeadSnap","CrystalAura","AnchorAura","AnchorFill",
    "AnchorPlace","BedAura","AutoBed","BedBomb","BedPlace","BowAimbot","BowSpam",
    "AutoBow","AutoCrit","CritBypass","AlwaysCrit","CriticalHit","ReachHack",
    "ExtendReach","LongReach","HitboxExpand","AntiKB","NoKnockback","GrimVelocity",
    "GrimDisabler","VelocitySpoof","KBReduce","OffhandTotem","TotemSwitch",
    "AutoWeapon","AutoSword","AutoCity","Burrow","SelfTrap","HoleFiller",
    "AntiSurround","AntiBurrow","WTap","TargetStrafe","AutoGap","AutoPearl",
    "FlyHack","CreativeFlight","BoatFly","PacketFly","AirJump","SpeedHack",
    "BHop","BunnyHop","AntiFall","NoFallDamage","SafeFall","StepHack","FastClimb",
    "AutoStep","HighStep","WaterWalk","LiquidWalk","LavaWalk","NoSlow","NoSlowdown",
    "NoWeb","NoSoulSand","WallHack","ElytraSpeed","InstantElytra","ScaffoldWalk",
    "FastBridge","BuildHelper","AutoBridge","Nuker","NukerLegit","InstantBreak",
    "GhostHand","NoSwing","PlaceAssist","AirPlace","AutoPlace","InstantPlace",
    "PlayerESP","MobESP","ItemESP","StorageESP","ChestESP","Tracers","NameTagsHack",
    "XRayHack","OreFinder","CaveFinder","OreESP","NewChunks","ChunkBorders",
    "TunnelFinder","TargetHUD","ReachDisplay","DoubleClicker","JitterClick",
    "ButterflyClick","CPSBoost","ChestStealer","InvManager","InvMovebypass",
    "AutoSprint","AntiAFK","AutoRespawn","PopSwitch","FakeLatency","FakePing",
    "SpoofRotation","PositionSpoof","GameSpeed","SpeedTimer",
    "GrimBypass","VulcanBypass","MatrixBypass","AACBypass","VerusDisabler",
    "IntaveBypass","WatchdogBypass","PacketMine","PacketWalk","PacketSneak",
    "PacketCancel","PacketDupe","PacketSpam","SelfDestruct","HideClient",
    "SessionStealer","TokenLogger","TokenGrabber","DiscordToken","RemoteAccess",
    "ReverseShell","C2Server","Backdoor","KeyLogger","StashFinder","TrailFinder",
    "imgui.binding","JNativeHook","GlobalScreen","NativeKeyListener",
    "client-refmap.json","cheat-refmap.json",
    "aHR0cDovL2FwaS5ub3ZhY2xpZW50LmxvbC93ZWJob29rLnR4dA==",
    "meteordevelopment","cc/novoline","com/alan/clients","club/maxstats",
    "wtf/moonlight","me/zeroeightsix/kami","net/ccbluex","today/opai",
    "net/minecraft/injection","org/chainlibs/module/impl/modules","xyz/greaj",
    "com/cheatbreaker","com/moonsworth","doomsdayclient","DoomsdayClient",
    "novaclient","api.novaclient.lol","WalksyOptimizer","LWFH Crystal",
    "vape.gg","vapeclient","VapeClient","VapeLite","intent.store","IntentClient",
    "rise.today","riseclient.com","meteor-client","meteorclient",
    "meteordevelopment.meteorclient","liquidbounce","fdp-client","net.ccbluex",
    "novoware","novoclient","aristois","impactclient","azura","pandaware",
    "skilled","moonClient","astolfo","futureClient","konas","rusherhack",
    "inertia","exhibition","dev.krypton","dev/krypton","skid.krypton",
    "VirginClient","catlean","CatleanClient","ArgonClient","Asteria",
    "AsteriaClient","Prestige","PrestigeClient","prestigeclient.vip","gypsy",
    "GypsyClient","Xenon","XenonClient","phantom-refmap.json","dqrkis.xyz",
    "Dqrkis Client","Macro198","macro198","198macros.com",
    # v2 additions
    "discordapp.com/api/webhooks","webhook.site","api.dqrkis",
    "bypassanticheat","anticheat.bypass","disableAnticheat",
    "getRuntime","ProcessBuilder","loadLibrary","loadClass",
    "URLClassLoader","defineClass","findClass","ClassLoader"
)

# Network-specific patterns (regex strings, used in Invoke-NetworkScan)
$networkPatterns = @(
    'discord(app)?\.com/api/webhooks/\d+',
    'webhook\.site/',
    'pastebin\.com/raw/',
    '\.ngrok\.io',
    'hastebin\.com/',
    'api\.novaclient\.lol',
    'prestigeclient\.vip',
    'dqrkis\.xyz',
    'doomsdayclient\.com',
    '198macros\.com',
    'raw\.githubusercontent\.com',
    'aHR0[A-Za-z0-9+/]{10,}={0,2}',         # base64-encoded URL
    '(?<![.\d])((?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)(?![.\d])'  # raw IPv4
)

$cheatStringSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($s in $cheatStrings) { [void]$cheatStringSet.Add($s) }

$patternRegex = [regex]::new(
    '(?<![A-Za-z])(' + (($suspiciousPatterns | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![A-Za-z])',
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

$fullwidthRegex = [regex]::new(
    "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]{2,}",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)

# ═══════════════════════════════════════════════════════════════════════════════
#  HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Get-FileSHA1 ([string]$Path) {
    try { return (Get-FileHash -Path $Path -Algorithm SHA1).Hash }
    catch { return $null }
}

function Get-DownloadSource ([string]$Path) {
    $zoneData = Get-Content -Raw -Stream Zone.Identifier $Path -ErrorAction SilentlyContinue
    if ($zoneData -match "HostUrl=(.+)") {
        $url = $matches[1].Trim()
        switch -Regex ($url) {
            "mediafire\.com"                                        { return "MediaFire" }
            "discord\.com|discordapp\.com|cdn\.discordapp\.com"    { return "Discord" }
            "dropbox\.com"                                          { return "Dropbox" }
            "drive\.google\.com"                                    { return "Google Drive" }
            "mega\.nz|mega\.co\.nz"                                { return "MEGA" }
            "github\.com"                                           { return "GitHub" }
            "modrinth\.com"                                         { return "Modrinth" }
            "curseforge\.com"                                       { return "CurseForge" }
            "doomsdayclient\.com"                                   { return "⚠ DoomsdayClient" }
            "prestigeclient\.vip"                                   { return "⚠ PrestigeClient" }
            "198macros\.com"                                        { return "⚠ 198Macros" }
            "dqrkis\.xyz"                                           { return "⚠ Dqrkis" }
            default {
                if ($url -match "https?://(?:www\.)?([^/]+)") { return $matches[1] }
                return $url.Substring(0, [math]::Min(40, $url.Length))
            }
        }
    }
    return $null
}

function Query-Modrinth ([string]$Hash) {
    try {
        $ver = Invoke-RestMethod "https://api.modrinth.com/v2/version_file/$Hash" -UseBasicParsing -EA Stop
        if ($ver.project_id) {
            $proj = Invoke-RestMethod "https://api.modrinth.com/v2/project/$($ver.project_id)" -UseBasicParsing -EA Stop
            return @{ Name = $proj.title; Slug = $proj.slug }
        }
    } catch {}
    return @{ Name = ""; Slug = "" }
}

function Query-Megabase ([string]$Hash) {
    try {
        $r = Invoke-RestMethod "https://megabase.vercel.app/api/query?hash=$Hash" -UseBasicParsing -EA Stop
        if (-not $r.error) { return $r.data }
    } catch {}
    return $null
}

function Get-ByteEntropy ([byte[]]$Bytes) {
    if ($Bytes.Length -lt 128) { return 0.0 }
    $freq = [double[]]::new(256)
    foreach ($b in $Bytes) { $freq[$b]++ }
    $H = 0.0
    $n = [double]$Bytes.Length
    foreach ($f in $freq) {
        if ($f -gt 0) {
            $p = $f / $n
            $H -= $p * [math]::Log($p, 2)
        }
    }
    return $H
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SCAN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-ModScan ([string]$FilePath) {
    $foundPatterns  = [System.Collections.Generic.HashSet[string]]::new()
    $foundStrings   = [System.Collections.Generic.HashSet[string]]::new()
    $foundFullwidth = [System.Collections.Generic.HashSet[string]]::new()

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)

        foreach ($entry in $archive.Entries) {
            foreach ($m in $patternRegex.Matches($entry.FullName)) {
                [void]$foundPatterns.Add($m.Value)
            }
        }

        $allEntries    = [System.Collections.Generic.List[object]]::new()
        $innerArchives = [System.Collections.Generic.List[object]]::new()

        foreach ($e in $archive.Entries) { $allEntries.Add($e) }

        foreach ($nj in ($archive.Entries | Where-Object { $_.FullName -match "^META-INF/jars/.+\.jar$" })) {
            try {
                $ns = $nj.Open()
                $ms = New-Object System.IO.MemoryStream
                $ns.CopyTo($ms); $ns.Close()
                $ms.Position = 0
                $iz = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
                $innerArchives.Add($iz)
                foreach ($ie in $iz.Entries) { $allEntries.Add($ie) }
            } catch {}
        }

        foreach ($entry in $allEntries) {
            $name = $entry.FullName
            if ($name -match '\.(class|json)$' -or $name -match 'MANIFEST\.MF') {
                try {
                    $st  = $entry.Open()
                    $ms2 = New-Object System.IO.MemoryStream
                    $st.CopyTo($ms2); $st.Close()
                    $bytes = $ms2.ToArray(); $ms2.Dispose()
                    $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
                    $utf8  = [System.Text.Encoding]::UTF8.GetString($bytes)

                    foreach ($m in $patternRegex.Matches($ascii)) { [void]$foundPatterns.Add($m.Value) }
                    foreach ($s in $cheatStringSet) {
                        if ($ascii.Contains($s) -or $utf8.Contains($s)) { [void]$foundStrings.Add($s) }
                    }
                    foreach ($m in $fullwidthRegex.Matches($utf8)) { [void]$foundFullwidth.Add($m.Value) }
                } catch {}
            }
        }

        foreach ($ia in $innerArchives) { try { $ia.Dispose() } catch {} }
        $archive.Dispose()
    } catch {}

    # Resolve fullwidth matches to known cheat string names
    $fwPool  = @($cheatStrings | Where-Object { $_ -cmatch "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]" })
    $resolved = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($fw in @($foundFullwidth)) {
        if ($fw.Length -lt 3) { continue }
        $best = $null
        foreach ($cs in $fwPool) {
            if ($cs.Contains($fw) -and ($null -eq $best -or $cs.Length -lt $best.Length)) { $best = $cs }
        }
        if ($null -ne $best) { [void]$resolved.Add($best) }
        elseif ($fw.Length -ge 6) { [void]$resolved.Add($fw) }
    }
    $finalFW = [System.Collections.Generic.HashSet[string]]::new()
    $resolvedArr = @($resolved)
    foreach ($fw in $resolvedArr) {
        $redundant = $false
        foreach ($other in $resolvedArr) {
            if ($fw.Length -lt $other.Length -and $other.Contains($fw)) { $redundant = $true; break }
        }
        if (-not $redundant) { [void]$finalFW.Add($fw) }
    }

    return @{ Patterns = $foundPatterns; Strings = $foundStrings; Fullwidth = $finalFW }
}

function Invoke-ObfuscationScan ([string]$FilePath) {
    $flags = [System.Collections.Generic.List[string]]::new()

    $cheatObfuscators = @{
        "Skidfuscator"   = @("dev/skidfuscator","Skidfuscator","skidfuscator.dev")
        "Paramorphism"   = @("Paramorphism","paramorphism-","dev/paramorphism")
        "Radon"          = @("ItzSomebody/Radon","me/itzsomebody/radon","Radon Obfuscator")
        "Caesium"        = @("sim0n/Caesium","Caesium Obfuscator","dev/sim0n/caesium")
        "Bozar"          = @("vimasig/Bozar","Bozar Obfuscator","com/bozar")
        "Branchlock"     = @("Branchlock","branchlock.dev")
        "Binscure"       = @("Binscure","com/binscure")
        "SuperBlaubeere" = @("superblaubeere","superblaubeere27")
        "Qprotect"       = @("Qprotect","QProtect","mdma.dev/qprotect")
        "Zelix"          = @("ZKMFLOW","ZKM","ZelixKlassMaster","com/zelix")
        "Stringer"       = @("StringerJavaObfuscator","com/licel/stringer")
        "JNIC"           = @("JNIC","jnic.obf","jnic-obfuscator")
        "Scuti"          = @("ScutiObf","scuti.obf")
        "Smoke"          = @("SmokeObf","smoke.obf")
    }

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)

        $totalClass     = 0
        $numericCount   = 0; $unicodeCount  = 0; $fullwidthCount = 0
        $japaneseCount  = 0; $singleLetter  = 0; $twoLetter      = 0
        $gibberish      = 0; $noVowel       = 0; $confusion      = 0; $singleCharPkg  = 0
        $highEntropyCount = 0; $totalClassBytes = 0
        $contentSample  = [System.Text.StringBuilder]::new()
        $sampleSize     = 0

        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match "\.class$") {
                $totalClass++
                $cn = [System.IO.Path]::GetFileNameWithoutExtension(($entry.FullName -split "/")[-1])
                if ($cn -match "^\d+$")                          { $numericCount++ }
                if ($cn -match "[^\x00-\x7F]")                   { $unicodeCount++ }
                if ($cn -match "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]") { $fullwidthCount++ }
                if ($cn -match "[\u3040-\u309F\u30A0-\u30FF]")  { $japaneseCount++ }
                if ($cn -match "^[a-zA-Z]$")                     { $singleLetter++ }
                if ($cn -match "^[a-zA-Z]{2}$")                  { $twoLetter++ }
                if ($cn -match "^[Il1O0]+$|^_+$")               { $confusion++ }

                if ($cn.Length -ge 3 -and $cn.Length -le 8 -and $cn -match "^[a-zA-Z]+$") {
                    $vowels = ($cn.ToCharArray() | Where-Object { $_ -match "[aeiouAEIOU]" }).Count
                    if ($vowels -eq 0) { $noVowel++ }
                    if ($cn -match "[bcdfghjklmnpqrstvwxyz]{3,}" -and ($vowels / $cn.Length) -lt 0.3) { $gibberish++ }
                }

                $segs = ($entry.FullName -replace "\.class$","") -split "/"
                foreach ($seg in $segs[0..($segs.Count-2)]) { if ($seg.Length -eq 1) { $singleCharPkg++ } }

                # Entropy analysis
                if ($entry.Length -gt 512 -and $entry.Length -lt 500000) {
                    try {
                        $st  = $entry.Open()
                        $ms  = New-Object System.IO.MemoryStream
                        $st.CopyTo($ms); $st.Close()
                        $b   = $ms.ToArray(); $ms.Dispose()
                        $H   = Get-ByteEntropy $b
                        if ($H -gt 7.2) { $highEntropyCount++ }
                        $totalClassBytes += $b.Length
                        if ($sampleSize -lt 120000) {
                            [void]$contentSample.Append([System.Text.Encoding]::ASCII.GetString($b))
                            $sampleSize += $b.Length
                        }
                    } catch {}
                }
            }
        }

        $archive.Dispose()
        if ($totalClass -lt 5) { return $flags }

        $pct = { param($n) [math]::Round(($n / $totalClass) * 100) }

        if ((& $pct $numericCount)  -ge 20) { $flags.Add("Numeric class names — {0}% of classes ({1} total)" -f (& $pct $numericCount), $numericCount) }
        if ((& $pct $unicodeCount)  -ge 10) { $flags.Add("Unicode class names — {0}% use non-ASCII characters" -f (& $pct $unicodeCount)) }
        if ($fullwidthCount          -gt  0) { $flags.Add("Fullwidth Unicode class names — {0} classes use ａｂｃ/ＡＢＣ chars" -f $fullwidthCount) }
        if ($japaneseCount           -gt  0) { $flags.Add("Japanese obfuscation — {0} classes use hiragana/katakana" -f $japaneseCount) }
        if ((& $pct $singleLetter)  -ge 15) { $flags.Add("Single-letter class names — {0}% ({1} classes)" -f (& $pct $singleLetter), $singleLetter) }
        if ((& $pct $twoLetter)     -ge 20) { $flags.Add("Two-letter class names — {0}% ({1} classes)" -f (& $pct $twoLetter), $twoLetter) }
        if ((& $pct $gibberish)     -ge  5) { $flags.Add("Gibberish class names — {0}% have consonant clusters / no vowels" -f (& $pct $gibberish)) }
        if ((& $pct $noVowel)       -ge  8) { $flags.Add("No-vowel class names — {0}% ({1} classes)" -f (& $pct $noVowel), $noVowel) }
        if ((& $pct $confusion)     -ge  3) { $flags.Add("Confusion-char names (Il1O0/_) — {0}% ({1} classes)" -f (& $pct $confusion), $confusion) }
        if ($singleCharPkg           -ge  6) { $flags.Add("Single-char package paths — {0} segments like a/b/c" -f $singleCharPkg) }

        # Entropy flag
        if ($totalClass -ge 10) {
            $entPct = [math]::Round(($highEntropyCount / $totalClass) * 100)
            if ($entPct -ge 20) { $flags.Add("High entropy class files — {0}% of classes ({1}) have entropy > 7.2 bits  (encrypted/packed code)" -f $entPct, $highEntropyCount) }
        }

        $fwMatches = [regex]::Matches($contentSample.ToString(), "[\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]{2,}")
        if ($fwMatches.Count -gt 0) {
            $examples = ($fwMatches | Select-Object -First 3 | ForEach-Object { $_.Value }) -join ", "
            $flags.Add("Fullwidth strings in class content — $($fwMatches.Count) occurrences: $examples")
        }

        $ss = $contentSample.ToString()
        foreach ($obfName in $cheatObfuscators.Keys) {
            foreach ($pat in $cheatObfuscators[$obfName]) {
                if ($ss.Contains($pat)) { $flags.Add("Known obfuscator — $obfName  (matched: $pat)"); break }
            }
        }

    } catch {}

    return $flags
}

function Invoke-BypassScan ([string]$FilePath) {
    $flags = [System.Collections.Generic.List[string]]::new()

    $mavenPrefixes = @("com_","org_","net_","io_","dev_","gs_","xyz_","app_","me_","tv_","uk_","be_","fr_","de_")

    function IsSuspiciousJar ([string]$Name) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        if ($base -match '\d') { return $false }
        foreach ($pfx in $mavenPrefixes) { if ($base.ToLower().StartsWith($pfx)) { return $false } }
        if ($base.Length -gt 20) { return $false }
        return $true
    }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)

        $nestedJars   = @($zip.Entries | Where-Object { $_.FullName -match "^META-INF/jars/.+\.jar$" })
        $outerClasses = @($zip.Entries | Where-Object { $_.FullName -match "\.class$" })

        foreach ($nj in $nestedJars) {
            $base = [System.IO.Path]::GetFileName($nj.FullName)
            if (IsSuspiciousJar $base) { $flags.Add("Suspicious nested JAR — no version, unknown dependency: $base") }
        }

        if ($nestedJars.Count -eq 1 -and $outerClasses.Count -lt 3) {
            $njn = [System.IO.Path]::GetFileName(($nestedJars | Select-Object -First 1).FullName)
            $flags.Add("Hollow shell — only $($outerClasses.Count) own class(es), wraps: $njn")
        }

        $outerModId = ""
        $fmje = $zip.Entries | Where-Object { $_.FullName -eq "fabric.mod.json" } | Select-Object -First 1
        if ($fmje) {
            try {
                $s = $fmje.Open(); $r = New-Object System.IO.StreamReader($s)
                $t = $r.ReadToEnd(); $r.Close(); $s.Close()
                if ($t -match '"id"\s*:\s*"([^"]+)"') { $outerModId = $matches[1] }
            } catch {}
        }

        $allEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $zip.Entries) { $allEntries.Add($e) }
        $innerZips  = [System.Collections.Generic.List[object]]::new()
        foreach ($nj in $nestedJars) {
            try {
                $ns = $nj.Open(); $ms = New-Object System.IO.MemoryStream
                $ns.CopyTo($ms); $ns.Close(); $ms.Position = 0
                $iz = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
                $innerZips.Add($iz); foreach ($ie in $iz.Entries) { $allEntries.Add($ie) }
            } catch {}
        }

        $runtimeExec   = $false; $httpDownload = $false; $httpExfil     = $false
        $manifestAgent = $false
        $obfCount = 0; $numCount = 0; $uniCount = 0; $total = 0

        foreach ($entry in $allEntries) {
            $name = $entry.FullName

            # MANIFEST agent check
            if ($name -match "MANIFEST\.MF") {
                try {
                    $st = $entry.Open(); $r = New-Object System.IO.StreamReader($st)
                    $t  = $r.ReadToEnd(); $r.Close(); $st.Close()
                    if ($t -match "Premain-Class|Agent-Class|Can-Redefine-Classes: true|Can-Retransform-Classes: true") {
                        $manifestAgent = $true
                    }
                } catch {}
            }

            if ($name -match "\.class$") {
                $total++
                $cn = [System.IO.Path]::GetFileNameWithoutExtension(($name -split "/")[-1])
                if ($cn -match "^\d+$")         { $numCount++ }
                if ($cn -match "[^\x00-\x7F]")  { $uniCount++ }
                $segs = ($name -replace "\.class$","") -split "/"
                $consec = 0; $maxC = 0
                foreach ($seg in $segs) {
                    $consec = if ($seg.Length -eq 1) { $consec+1 } else { 0 }
                    if ($consec -gt $maxC) { $maxC = $consec }
                }
                if ($maxC -ge 3) { $obfCount++ }

                try {
                    $st  = $entry.Open(); $ms2 = New-Object System.IO.MemoryStream
                    $st.CopyTo($ms2); $st.Close()
                    $ct = [System.Text.Encoding]::ASCII.GetString($ms2.ToArray()); $ms2.Dispose()

                    if ($ct -match "java/lang/Runtime" -and $ct -match "getRuntime" -and $ct -match "exec") { $runtimeExec   = $true }
                    if ($ct -match "openConnection"    -and $ct -match "HttpURLConnection" -and $ct -match "FileOutputStream") { $httpDownload = $true }
                    if ($ct -match "openConnection"    -and $ct -match "setDoOutput" -and $ct -match "getOutputStream" -and $ct -match "getProperty") { $httpExfil = $true }
                } catch {}
            }
        }

        foreach ($iz in $innerZips) { try { $iz.Dispose() } catch {} }
        $zip.Dispose()

        $obfPct = if ($total -ge 10) { [math]::Round(($obfCount / $total) * 100) } else { 0 }
        $numPct = if ($total -ge 5)  { [math]::Round(($numCount / $total) * 100) } else { 0 }
        $uniPct = if ($total -ge 5)  { [math]::Round(($uniCount / $total) * 100) } else { 0 }

        if ($manifestAgent)                       { $flags.Add("MANIFEST declares Java agent — Premain-Class / Agent-Class / Can-Redefine-Classes") }
        if ($runtimeExec -and $obfPct -ge 25)     { $flags.Add("Runtime.exec() in obfuscated code — can run arbitrary OS commands") }
        if ($httpDownload)                         { $flags.Add("HTTP file download — fetches and writes files from a remote server at runtime") }
        if ($httpExfil)                            { $flags.Add("HTTP POST exfiltration — sends system data to an external server") }
        if ($total -ge 10 -and $obfPct -ge 25)    { $flags.Add("Heavy obfuscation — $obfPct% of classes use single-letter path segments (a/b/c)") }
        if ($numPct -ge 20)                        { $flags.Add("Numeric class names — $numPct% of classes have numeric-only names") }
        if ($uniPct -ge 10)                        { $flags.Add("Unicode class names — $uniPct% use non-ASCII characters") }

        $legitIds = @("vmp-fabric","vmp","lithium","sodium","iris","fabric-api","modmenu",
                      "ferrite-core","lazydfu","starlight","entityculling","memoryleakfix",
                      "krypton","c2me-fabric","smoothboot-fabric","immediatelyfast",
                      "noisium","threadtweak","modernfix")
        $danger = ($flags | Where-Object { $_ -match "Runtime\.exec|HTTP file|HTTP POST|Suspicious nested" }).Count
        if ($outerModId -and ($legitIds -contains $outerModId) -and $danger -gt 0) {
            $flags.Add("Fake mod identity — claims to be '$outerModId' but contains dangerous code")
        }

    } catch {}

    return $flags
}

function Invoke-NetworkScan ([string]$FilePath) {
    $found = [System.Collections.Generic.HashSet[string]]::new()

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $allEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $archive.Entries) { $allEntries.Add($e) }

        foreach ($nj in ($archive.Entries | Where-Object { $_.FullName -match "^META-INF/jars/.+\.jar$" })) {
            try {
                $ns = $nj.Open(); $ms = New-Object System.IO.MemoryStream
                $ns.CopyTo($ms); $ns.Close(); $ms.Position = 0
                $iz = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Read)
                foreach ($ie in $iz.Entries) { $allEntries.Add($ie) }
            } catch {}
        }

        foreach ($entry in $allEntries) {
            if ($entry.FullName -match "\.(class|json|txt|properties)$" -or $entry.FullName -match "MANIFEST\.MF") {
                try {
                    $st  = $entry.Open(); $ms2 = New-Object System.IO.MemoryStream
                    $st.CopyTo($ms2); $st.Close()
                    $text = [System.Text.Encoding]::UTF8.GetString($ms2.ToArray()); $ms2.Dispose()

                    foreach ($pat in $networkPatterns) {
                        $matches2 = [regex]::Matches($text, $pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                        foreach ($m in $matches2) {
                            $val = $m.Value.Trim()
                            # Skip common/benign false positives
                            if ($val -match "^127\.|^0\.0\.0\.0$|^255\.|^192\.168\.|^10\.|^172\.(1[6-9]|2\d|3[01])\.") { continue }
                            if ($val -match "minecraft\.net|mojang\.com|amazonaws\.com|cloudflare|googleapis\.com|modrinth\.com|curseforge\.com") { continue }
                            [void]$found.Add($val)
                        }
                    }
                } catch {}
            }
        }

        $archive.Dispose()
    } catch {}

    return $found
}

function Invoke-JvmScan {
    $results = [System.Collections.Generic.List[string]]::new()
    $jProc = Get-Process javaw -ErrorAction SilentlyContinue
    if (-not $jProc) { $jProc = Get-Process java -ErrorAction SilentlyContinue }
    if (-not $jProc) { return $results }

    $javaPid = ($jProc | Select-Object -First 1).Id
    try {
        $wmi     = Get-WmiObject Win32_Process -Filter "ProcessId = $javaPid" -EA Stop
        $cmdLine = $wmi.CommandLine
        if ($cmdLine) {
            foreach ($m in [regex]::Matches($cmdLine, '-javaagent:([^\s"]+)')) {
                $agentPath = $m.Groups[1].Value.Trim('"').Trim("'")
                $agentName = [System.IO.Path]::GetFileName($agentPath)
                $legitAgents = @("jmxremote","yjp","jrebel","newrelic","jacoco","theseus")
                $isLegit = $false
                foreach ($la in $legitAgents) { if ($agentName -match $la) { $isLegit = $true; break } }
                if (-not $isLegit) { $results.Add("JVM Agent — -javaagent:$agentName  (path: $agentPath)") }
            }

            @(
                @{ F = "-Xbootclasspath/p:"; D = "prepends to bootstrap classpath — overrides core Java classes" }
                @{ F = "-Xbootclasspath/a:"; D = "appends to bootstrap classpath — injects below classloader" }
                @{ F = "-agentlib:jdwp";     D = "JDWP debug agent enabled — allows remote debugging/code injection" }
                @{ F = "-agentpath:";        D = "native agent loaded — bypasses Java security sandbox" }
            ) | ForEach-Object {
                if ($cmdLine -match [regex]::Escape($_.F)) {
                    $results.Add("Suspicious JVM flag — $($_.F)  $($_.D)")
                }
            }
        }
    } catch {}

    return $results
}

# ═══════════════════════════════════════════════════════════════════════════════
#  RISK SCORING
# ═══════════════════════════════════════════════════════════════════════════════

function Get-RiskScore {
    param($Scan, $Bypass, $Obf, $Network)
    $s = 0
    if ($Scan.Patterns -and $Scan.Patterns.Count -gt 0) { $s += [math]::Min(40, $Scan.Patterns.Count * 10) }
    if ($Scan.Strings  -and $Scan.Strings.Count  -gt 0) { $s += [math]::Min(30, $Scan.Strings.Count  *  5) }
    if ($Scan.Fullwidth -and $Scan.Fullwidth.Count -gt 0) { $s += [math]::Min(15, $Scan.Fullwidth.Count * 5) }
    if ($Bypass        -and $Bypass.Count          -gt 0) { $s += [math]::Min(60, $Bypass.Count * 20) }
    if ($Network       -and $Network.Count         -gt 0) { $s += [math]::Min(45, $Network.Count * 15) }
    if ($Obf           -and $Obf.Count             -gt 0) { $s += [math]::Min(15, $Obf.Count    *  3) }
    return [math]::Min(100, $s)
}

# ═══════════════════════════════════════════════════════════════════════════════
#  OUTPUT CARDS
# ═══════════════════════════════════════════════════════════════════════════════

function Write-SuspiciousCard ($Mod) {
    $c = "DarkRed"
    Write-Host ("  ┌" + "─" * 72 + "┐") -ForegroundColor $c
    Write-Host "  │ " -ForegroundColor $c -NoNewline
    Write-Host " SUSPICIOUS " -ForegroundColor White -BackgroundColor DarkRed -NoNewline
    Write-Host "  " -NoNewline
    Write-Host $Mod.FileName -ForegroundColor Yellow
    Write-Host "  │  " -ForegroundColor $c -NoNewline; RiskBadge $Mod.Risk
    Write-Host ("  ├" + "─" * 72 + "┤") -ForegroundColor $c

    if ($Mod.Patterns.Count -gt 0) {
        Write-Host "  │  " -ForegroundColor $c -NoNewline; Write-Host "PATTERNS  ($($Mod.Patterns.Count))" -ForegroundColor DarkGray
        foreach ($p in ($Mod.Patterns | Sort-Object)) {
            Write-Host "  │    " -ForegroundColor $c -NoNewline
            Write-Host "◆ " -ForegroundColor Red -NoNewline
            Write-Host $p -ForegroundColor Red
        }
    }

    $uniqStr = @($Mod.Strings | Where-Object { $Mod.Patterns -notcontains $_ } | Sort-Object)
    if ($uniqStr.Count -gt 0) {
        Write-Host "  │" -ForegroundColor $c
        Write-Host "  │  " -ForegroundColor $c -NoNewline; Write-Host "STRINGS  ($($uniqStr.Count))" -ForegroundColor DarkGray
        foreach ($s in $uniqStr) {
            Write-Host "  │    " -ForegroundColor $c -NoNewline
            Write-Host "▸ " -ForegroundColor DarkYellow -NoNewline
            Write-Host $s -ForegroundColor DarkYellow
        }
    }

    if ($Mod.Fullwidth -and $Mod.Fullwidth.Count -gt 0) {
        Write-Host "  │" -ForegroundColor $c
        Write-Host "  │  " -ForegroundColor $c -NoNewline; Write-Host "FULLWIDTH UNICODE  ($($Mod.Fullwidth.Count))" -ForegroundColor DarkGray
        foreach ($fw in ($Mod.Fullwidth | Sort-Object)) {
            Write-Host "  │    " -ForegroundColor $c -NoNewline
            Write-Host "⊕ " -ForegroundColor Cyan -NoNewline
            Write-Host $fw -ForegroundColor Cyan
        }
    }

    Write-Host ("  └" + "─" * 72 + "┘") -ForegroundColor $c
    Blank
}

function Write-BypassCard ($Mod) {
    $c = "DarkMagenta"
    Write-Host ("  ┌" + "─" * 72 + "┐") -ForegroundColor $c
    Write-Host "  │ " -ForegroundColor $c -NoNewline
    Write-Host " BYPASS / INJECT " -ForegroundColor White -BackgroundColor DarkMagenta -NoNewline
    Write-Host "  " -NoNewline
    Write-Host $Mod.FileName -ForegroundColor Yellow
    Write-Host "  │  " -ForegroundColor $c -NoNewline; RiskBadge $Mod.Risk
    Write-Host ("  ├" + "─" * 72 + "┤") -ForegroundColor $c
    foreach ($flag in $Mod.Flags) {
        $title = $flag; $desc = ""
        if ($flag -match "^(.+?) — (.+)$") { $title = $matches[1]; $desc = $matches[2] }
        Write-Host "  │" -ForegroundColor $c
        Write-Host "  │    " -ForegroundColor $c -NoNewline
        Write-Host "◉ " -ForegroundColor Magenta -NoNewline
        Write-Host $title -ForegroundColor White
        if ($desc) { Write-Host "  │      " -ForegroundColor $c -NoNewline; Write-Host $desc -ForegroundColor Gray }
    }
    Write-Host "  │" -ForegroundColor $c
    Write-Host ("  └" + "─" * 72 + "┘") -ForegroundColor $c
    Blank
}

function Write-ObfuscationCard ($Mod) {
    $c = "DarkYellow"
    Write-Host ("  ┌" + "─" * 72 + "┐") -ForegroundColor $c
    Write-Host "  │ " -ForegroundColor $c -NoNewline
    Write-Host " OBFUSCATED " -ForegroundColor Black -BackgroundColor DarkYellow -NoNewline
    Write-Host "  " -NoNewline
    Write-Host $Mod.FileName -ForegroundColor Yellow
    Write-Host "  │  " -ForegroundColor $c -NoNewline; RiskBadge $Mod.Risk
    Write-Host ("  ├" + "─" * 72 + "┤") -ForegroundColor $c
    foreach ($flag in $Mod.Flags) {
        $title = $flag; $desc = ""
        if ($flag -match "^(.+?) — (.+)$") { $title = $matches[1]; $desc = $matches[2] }
        Write-Host "  │" -ForegroundColor $c
        Write-Host "  │    " -ForegroundColor $c -NoNewline
        Write-Host "⚑ " -ForegroundColor Yellow -NoNewline
        Write-Host $title -ForegroundColor White
        if ($desc) { Write-Host "  │      " -ForegroundColor $c -NoNewline; Write-Host $desc -ForegroundColor Gray }
    }
    Write-Host "  │" -ForegroundColor $c
    Write-Host ("  └" + "─" * 72 + "┘") -ForegroundColor $c
    Blank
}

function Write-NetworkCard ($Mod) {
    $c = "DarkBlue"
    Write-Host ("  ┌" + "─" * 72 + "┐") -ForegroundColor $c
    Write-Host "  │ " -ForegroundColor $c -NoNewline
    Write-Host " NETWORK INDICATOR " -ForegroundColor White -BackgroundColor DarkBlue -NoNewline
    Write-Host "  " -NoNewline
    Write-Host $Mod.FileName -ForegroundColor Yellow
    Write-Host "  │  " -ForegroundColor $c -NoNewline; RiskBadge $Mod.Risk
    Write-Host ("  ├" + "─" * 72 + "┤") -ForegroundColor $c
    Write-Host "  │" -ForegroundColor $c
    Write-Host "  │  " -ForegroundColor $c -NoNewline; Write-Host "FOUND  ($($Mod.Indicators.Count))" -ForegroundColor DarkGray
    foreach ($ind in ($Mod.Indicators | Sort-Object)) {
        $display = if ($ind.Length -gt 62) { $ind.Substring(0,59) + "..." } else { $ind }
        Write-Host "  │    " -ForegroundColor $c -NoNewline
        Write-Host "⬡ " -ForegroundColor Blue -NoNewline
        Write-Host $display -ForegroundColor Blue
    }
    Write-Host "  │" -ForegroundColor $c
    Write-Host ("  └" + "─" * 72 + "┘") -ForegroundColor $c
    Blank
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN SCAN LOOP
# ═══════════════════════════════════════════════════════════════════════════════

$verifiedMods    = @()
$unknownMods     = @()
$suspiciousMods  = @()
$bypassMods      = @()
$obfuscatedMods  = @()
$networkMods     = @()
$riskScores      = @{}
$jvmFlags        = @()

$total  = $jarFiles.Count
$idx    = 0

# ── Pass 1: Hash verification ─────────────────────────────────────────────────
Blank
Rule "═" Blue
Write-Host "  SCAN START  ·  $total file(s)  ·  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Rule "═" Blue
Blank
Write-Host "  ┌─ Pass 1  " -ForegroundColor DarkCyan -NoNewline
Write-Host "Hash Verification" -ForegroundColor White -NoNewline
Write-Host "  (Modrinth + Megabase)" -ForegroundColor DarkGray

Start-Pass "Pass 1  Hash Verification"

$idx = 0
foreach ($jar in $jarFiles) {
    $idx++
    ProgressBar $idx $total $jar.Name Blue

    $hash = Get-FileSHA1 $jar.FullName
    if ($hash) {
        $md = Query-Modrinth $hash
        if ($md.Slug) {
            $whitelist = @("viafabricplus","viafabricversion")
            $verifiedMods += [PSCustomObject]@{
                ModName   = $md.Name
                FileName  = $jar.Name
                FilePath  = $jar.FullName
                Whitelisted = ($whitelist -contains $md.Slug.ToLower())
            }
            continue
        }
        $mb = Query-Megabase $hash
        if ($mb.name) {
            $verifiedMods += [PSCustomObject]@{
                ModName   = $mb.name
                FileName  = $jar.Name
                FilePath  = $jar.FullName
                Whitelisted = $false
            }
            continue
        }
    }
    $src = Get-DownloadSource $jar.FullName
    $unknownMods += [PSCustomObject]@{ FileName = $jar.Name; FilePath = $jar.FullName; Source = $src }
}

Stop-Pass -Issues $unknownMods.Count -Extra "$($verifiedMods.Count) verified  ·  $($unknownMods.Count) unknown"
$p1 = $script:PassLog["Pass 1  Hash Verification"]
PassDone "Hash Verification" (Fmt-Span $p1.S $p1.E) $unknownMods.Count "$($verifiedMods.Count) verified  ·  $($unknownMods.Count) unknown"

# ── Pass 2: Cheat string scan ─────────────────────────────────────────────────
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  ├─ Pass 2  " -ForegroundColor DarkCyan -NoNewline
Write-Host "Cheat Signature Scan" -ForegroundColor White -NoNewline
Write-Host "  (strings · patterns · fullwidth)" -ForegroundColor DarkGray

Start-Pass "Pass 2  Cheat Signature Scan"
$idx = 0

foreach ($jar in $jarFiles) {
    $idx++
    ProgressBar $idx $total $jar.Name Red

    $ve = $verifiedMods | Where-Object { $_.FileName -eq $jar.Name -and $_.Whitelisted -eq $true } | Select-Object -First 1
    if ($ve) { continue }

    $r = Invoke-ModScan $jar.FullName

    if ($r.Patterns.Count -gt 0 -or $r.Strings.Count -gt 0 -or $r.Fullwidth.Count -gt 0) {
        $score = Get-RiskScore $r @() @() @()
        $riskScores[$jar.Name] = $score

        $suspiciousMods += [PSCustomObject]@{
            FileName = $jar.Name
            Patterns = $r.Patterns
            Strings  = $r.Strings
            Fullwidth = $r.Fullwidth
            Risk     = $score
        }
        $verifiedMods = $verifiedMods | Where-Object { $_.FileName -ne $jar.Name }
    }
}

Stop-Pass -Issues $suspiciousMods.Count
$p2 = $script:PassLog["Pass 2  Cheat Signature Scan"]
PassDone "Cheat Signature Scan" (Fmt-Span $p2.S $p2.E) $suspiciousMods.Count

# ── Pass 3: Bypass / Injection ────────────────────────────────────────────────
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  ├─ Pass 3  " -ForegroundColor DarkCyan -NoNewline
Write-Host "Bypass / Injection Scan" -ForegroundColor White -NoNewline
Write-Host "  (manifest · runtime · HTTP · obfuscation)" -ForegroundColor DarkGray

Start-Pass "Pass 3  Bypass / Injection Scan"
$idx = 0

foreach ($jar in $jarFiles) {
    $idx++
    ProgressBar $idx $total $jar.Name Magenta

    $ve = $verifiedMods | Where-Object { $_.FileName -eq $jar.Name -and $_.Whitelisted -eq $true } | Select-Object -First 1
    if ($ve) { continue }

    $flags = Invoke-BypassScan $jar.FullName

    if ($flags.Count -gt 0) {
        $existScan = $suspiciousMods | Where-Object { $_.FileName -eq $jar.Name } | Select-Object -First 1
        $prevScore  = if ($riskScores.ContainsKey($jar.Name)) { $riskScores[$jar.Name] } else { 0 }
        $score      = [math]::Min(100, $prevScore + (Get-RiskScore @{Patterns=@();Strings=@();Fullwidth=@()} $flags @() @()))

        $riskScores[$jar.Name] = $score
        $bypassMods += [PSCustomObject]@{ FileName = $jar.Name; Flags = $flags; Risk = $score }
        $verifiedMods = $verifiedMods | Where-Object { $_.FileName -ne $jar.Name }
        $unknownMods  = $unknownMods  | Where-Object { $_.FileName -ne $jar.Name }
    }
}

Stop-Pass -Issues $bypassMods.Count
$p3 = $script:PassLog["Pass 3  Bypass / Injection Scan"]
PassDone "Bypass / Injection Scan" (Fmt-Span $p3.S $p3.E) $bypassMods.Count

# ── Pass 4: Obfuscation + Entropy ─────────────────────────────────────────────
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  ├─ Pass 4  " -ForegroundColor DarkCyan -NoNewline
Write-Host "Obfuscation + Entropy" -ForegroundColor White -NoNewline
Write-Host "  (class names · entropy · known obfuscators)" -ForegroundColor DarkGray

Start-Pass "Pass 4  Obfuscation + Entropy"
$idx = 0

foreach ($jar in $jarFiles) {
    $idx++
    ProgressBar $idx $total $jar.Name DarkYellow

    $alreadyFlagged = ($suspiciousMods | Where-Object { $_.FileName -eq $jar.Name }).Count -gt 0 -or
                      ($bypassMods     | Where-Object { $_.FileName -eq $jar.Name }).Count -gt 0
    if ($alreadyFlagged) { continue }

    $flags = Invoke-ObfuscationScan $jar.FullName

    if ($flags.Count -gt 0) {
        $prevScore = if ($riskScores.ContainsKey($jar.Name)) { $riskScores[$jar.Name] } else { 0 }
        $score     = [math]::Min(100, $prevScore + [math]::Min(15, $flags.Count * 3))
        $riskScores[$jar.Name] = $score

        $obfuscatedMods += [PSCustomObject]@{ FileName = $jar.Name; Flags = $flags; Risk = $score }
        $verifiedMods    = $verifiedMods | Where-Object { $_.FileName -ne $jar.Name }
    }
}

Stop-Pass -Issues $obfuscatedMods.Count
$p4 = $script:PassLog["Pass 4  Obfuscation + Entropy"]
PassDone "Obfuscation + Entropy" (Fmt-Span $p4.S $p4.E) $obfuscatedMods.Count

# ── Pass 5: Network Indicators ────────────────────────────────────────────────
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  ├─ Pass 5  " -ForegroundColor DarkCyan -NoNewline
Write-Host "Network Indicator Scan" -ForegroundColor White -NoNewline
Write-Host "  (webhooks · IPs · C2 URLs)" -ForegroundColor DarkGray

Start-Pass "Pass 5  Network Indicator Scan"
$idx = 0

foreach ($jar in $jarFiles) {
    $idx++
    ProgressBar $idx $total $jar.Name Blue

    $ve = $verifiedMods | Where-Object { $_.FileName -eq $jar.Name -and $_.Whitelisted -eq $true } | Select-Object -First 1
    if ($ve) { continue }

    $indicators = Invoke-NetworkScan $jar.FullName

    if ($indicators.Count -gt 0) {
        $prevScore = if ($riskScores.ContainsKey($jar.Name)) { $riskScores[$jar.Name] } else { 0 }
        $score     = [math]::Min(100, $prevScore + [math]::Min(45, $indicators.Count * 15))
        $riskScores[$jar.Name] = $score

        $networkMods += [PSCustomObject]@{ FileName = $jar.Name; Indicators = $indicators; Risk = $score }
        $verifiedMods  = $verifiedMods | Where-Object { $_.FileName -ne $jar.Name }
        $unknownMods   = $unknownMods  | Where-Object { $_.FileName -ne $jar.Name }
    }
}

Stop-Pass -Issues $networkMods.Count
$p5 = $script:PassLog["Pass 5  Network Indicator Scan"]
PassDone "Network Indicator Scan" (Fmt-Span $p5.S $p5.E) $networkMods.Count

# ── Pass 6: JVM Runtime ───────────────────────────────────────────────────────
Write-Host "  │" -ForegroundColor DarkCyan
Write-Host "  └─ Pass 6  " -ForegroundColor DarkCyan -NoNewline
Write-Host "JVM Runtime" -ForegroundColor White -NoNewline
Write-Host "  (agents · JVM flags)" -ForegroundColor DarkGray

Start-Pass "Pass 6  JVM Runtime"
$jvmFlags = Invoke-JvmScan
Stop-Pass -Issues $jvmFlags.Count

ClearLine
$p6 = $script:PassLog["Pass 6  JVM Runtime"]
Write-Host "  └─ " -ForegroundColor DarkCyan -NoNewline
Write-Host ("JVM Runtime".PadRight(30)) -ForegroundColor White -NoNewline
if ($jvmFlags.Count -gt 0) {
    Write-Host ("⚠  " + "$($jvmFlags.Count) flagged".PadRight(15)) -ForegroundColor Yellow -NoNewline
} else {
    Write-Host ("✓  " + "clean".PadRight(15)) -ForegroundColor DarkGray -NoNewline
}
Write-Host "[$((Fmt-Span $p6.S $p6.E))]" -ForegroundColor DarkGray
Blank
Rule "═" Blue
Write-Host "  SCAN COMPLETE  ·  Total time: " -ForegroundColor Cyan -NoNewline
Write-Host (Get-TotalElapsed) -ForegroundColor White
Rule "═" Blue

# ═══════════════════════════════════════════════════════════════════════════════
#  RESULTS OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Verified ──────────────────────────────────────────────────────────────────
if ($verifiedMods.Count -gt 0) {
    SectHeader "✓" "VERIFIED MODS" $verifiedMods.Count Green
    foreach ($mod in $verifiedMods) {
        Write-Host "  ✓  " -ForegroundColor Green -NoNewline
        Write-Host "$($mod.ModName)" -ForegroundColor White -NoNewline
        Write-Host "  →  " -ForegroundColor DarkGray -NoNewline
        Write-Host $mod.FileName -ForegroundColor DarkGray
    }
    Blank
}

# ── Unknown ───────────────────────────────────────────────────────────────────
if ($unknownMods.Count -gt 0) {
    SectHeader "?" "UNKNOWN MODS" $unknownMods.Count Yellow
    foreach ($mod in $unknownMods) {
        $n = if ($mod.FileName.Length -gt 52) { $mod.FileName.Substring(0,49) + "..." } else { $mod.FileName }
        $srcText = if ($mod.Source) { "Source: $($mod.Source)" } else { "Source: unknown" }
        Write-Host ("  ┌─ ? " + $n + " " + ("─" * ([math]::Max(0, 67 - $n.Length))) + "┐") -ForegroundColor Yellow
        Write-Host ("  └─ " + $srcText + " " + ("─" * ([math]::Max(0, 67 - $srcText.Length))) + "┘") -ForegroundColor Yellow
        Blank
    }
}

# ── Suspicious ────────────────────────────────────────────────────────────────
if ($suspiciousMods.Count -gt 0) {
    SectHeader "⚠" "SUSPICIOUS MODS" $suspiciousMods.Count Red
    $suspiciousMods | Sort-Object { -$_.Risk } | ForEach-Object { Write-SuspiciousCard $_ }
}

# ── Bypass / Injection ────────────────────────────────────────────────────────
if ($bypassMods.Count -gt 0) {
    SectHeader "⬡" "BYPASS / INJECTION" $bypassMods.Count Magenta
    $bypassMods | Sort-Object { -$_.Risk } | ForEach-Object { Write-BypassCard $_ }
}

# ── Obfuscated ────────────────────────────────────────────────────────────────
if ($obfuscatedMods.Count -gt 0) {
    SectHeader "⚑" "OBFUSCATED MODS" $obfuscatedMods.Count Yellow
    $obfuscatedMods | Sort-Object { -$_.Risk } | ForEach-Object { Write-ObfuscationCard $_ }
}

# ── Network ───────────────────────────────────────────────────────────────────
if ($networkMods.Count -gt 0) {
    SectHeader "⬢" "NETWORK INDICATORS" $networkMods.Count Blue
    $networkMods | Sort-Object { -$_.Risk } | ForEach-Object { Write-NetworkCard $_ }
}

# ── JVM ───────────────────────────────────────────────────────────────────────
if ($jvmFlags.Count -gt 0) {
    SectHeader "⚡" "JVM / RUNTIME INJECTION" $jvmFlags.Count Yellow
    $c = "DarkYellow"
    Write-Host ("  ┌" + "─" * 72 + "┐") -ForegroundColor $c
    Write-Host "  │ " -ForegroundColor $c -NoNewline
    Write-Host " JVM " -ForegroundColor Black -BackgroundColor Yellow -NoNewline
    Write-Host "  javaw / java process" -ForegroundColor Yellow
    Write-Host ("  ├" + "─" * 72 + "┤") -ForegroundColor $c
    foreach ($flag in $jvmFlags) {
        $t = $flag; $d = ""; $fp = ""
        if ($flag -match "^(.+?) — (.+) \(path: (.+)\)$") { $t=$matches[1]; $d=$matches[2]; $fp=$matches[3] }
        elseif ($flag -match "^(.+?) — (.+)$")             { $t=$matches[1]; $d=$matches[2] }
        Write-Host "  │" -ForegroundColor $c
        Write-Host "  │    " -ForegroundColor $c -NoNewline
        Write-Host "◉ " -ForegroundColor Yellow -NoNewline
        Write-Host $t -ForegroundColor White
        if ($d)  { Write-Host "  │      " -ForegroundColor $c -NoNewline; Write-Host $d  -ForegroundColor Gray }
        if ($fp) {
            $dp = if ($fp.Length -gt 58) { "..." + $fp.Substring($fp.Length-55) } else { $fp }
            Write-Host "  │      " -ForegroundColor $c -NoNewline; Write-Host $dp -ForegroundColor DarkGray
        }
    }
    Write-Host "  │" -ForegroundColor $c
    Write-Host ("  └" + "─" * 72 + "┘") -ForegroundColor $c
    Blank
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SUMMARY + TIMING TABLE
# ═══════════════════════════════════════════════════════════════════════════════

Blank
Rule "═" DarkCyan
Write-Host "  📊  SCAN SUMMARY" -ForegroundColor Cyan
Rule "═" DarkCyan
Blank

# Stats table
$colW = 32
Write-Host "  " -NoNewline
Write-Host ("Total files scanned".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $total -ForegroundColor White
Write-Host "  " -NoNewline
Write-Host ("Verified".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $verifiedMods.Count -ForegroundColor Green
Write-Host "  " -NoNewline
Write-Host ("Unknown".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $unknownMods.Count -ForegroundColor Yellow
Write-Host "  " -NoNewline
Write-Host ("Suspicious (cheat signatures)".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $suspiciousMods.Count -ForegroundColor Red
Write-Host "  " -NoNewline
Write-Host ("Bypass / Injected".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $bypassMods.Count -ForegroundColor Magenta
Write-Host "  " -NoNewline
Write-Host ("Obfuscated".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $obfuscatedMods.Count -ForegroundColor Yellow
Write-Host "  " -NoNewline
Write-Host ("Network indicators".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $networkMods.Count -ForegroundColor Blue
Write-Host "  " -NoNewline
Write-Host ("JVM issues".PadRight($colW)) -ForegroundColor Gray -NoNewline
Write-Host $jvmFlags.Count -ForegroundColor Yellow

Blank
Rule "─" DarkGray

# Timing table
Write-Host "  ⏱  TIMING BREAKDOWN" -ForegroundColor DarkCyan
Blank

foreach ($key in $script:PassLog.Keys) {
    $entry = $script:PassLog[$key]
    if ($entry.S -and $entry.E) {
        $dur    = Fmt-Span $entry.S $entry.E
        $issues = $entry.I
        $label  = $key.PadRight(36)
        $durStr = $dur.PadLeft(8)
        Write-Host "    $label" -ForegroundColor Gray -NoNewline
        Write-Host $durStr -ForegroundColor White -NoNewline
        if ($issues -gt 0) {
            Write-Host "   ⚠ $issues" -ForegroundColor Yellow
        } else {
            Write-Host "   ✓" -ForegroundColor DarkGray
        }
    }
}

Blank
$totalStr = "  Total scan time:  " + (Get-TotalElapsed)
Write-Host $totalStr -ForegroundColor Cyan
Write-Host "  Scan date:        $scanDate" -ForegroundColor DarkGray

Blank
Rule "═" DarkCyan
Blank

# ── Top risk mods summary ─────────────────────────────────────────────────────
$allFlagged = @($suspiciousMods + $bypassMods + $obfuscatedMods + $networkMods) |
    Where-Object { $riskScores.ContainsKey($_.FileName) } |
    Sort-Object { -$riskScores[$_.FileName] } |
    Select-Object -First 5

if ($allFlagged.Count -gt 0) {
    Write-Host "  🔴  TOP RISK MODS" -ForegroundColor Red
    Blank
    $rank = 1
    foreach ($mod in $allFlagged) {
        $score = $riskScores[$mod.FileName]
        Write-Host "  $rank.  " -ForegroundColor DarkGray -NoNewline
        Write-Host $mod.FileName -ForegroundColor Yellow -NoNewline
        Write-Host "  " -NoNewline
        RiskBadge $score
        $rank++
    }
    Blank
    Rule "─" DarkGray
    Blank
}

# ── Log export prompt ─────────────────────────────────────────────────────────
Write-Host "  💾  Save scan report to file? " -ForegroundColor DarkGray -NoNewline
Write-Host "[Y/N]" -ForegroundColor White -NoNewline
Write-Host "  " -NoNewline
$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

if ($key.Character -match "[Yy]") {
    $logDir  = "$env:USERPROFILE\Desktop"
    $logName = "PannModCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $logPath = Join-Path $logDir $logName

    $lines = @()
    $lines += "PANN MOD CHECK v2.0  |  Scan Report"
    $lines += "Scan date  : $scanDate"
    $lines += "Mods path  : $modsPath"
    $lines += "Total files: $total"
    $lines += ""
    $lines += "RESULTS"
    $lines += ("─" * 60)
    $lines += "Verified       : $($verifiedMods.Count)"
    $lines += "Unknown        : $($unknownMods.Count)"
    $lines += "Suspicious     : $($suspiciousMods.Count)"
    $lines += "Bypass/Inject  : $($bypassMods.Count)"
    $lines += "Obfuscated     : $($obfuscatedMods.Count)"
    $lines += "Network        : $($networkMods.Count)"
    $lines += "JVM issues     : $($jvmFlags.Count)"
    $lines += ""
    $lines += "TIMING"
    $lines += ("─" * 60)
    foreach ($key2 in $script:PassLog.Keys) {
        $e = $script:PassLog[$key2]
        if ($e.S -and $e.E) { $lines += "$key2  $(Fmt-Span $e.S $e.E)" }
    }
    $lines += "Total: $(Get-TotalElapsed)"
    $lines += ""

    if ($suspiciousMods.Count -gt 0) {
        $lines += "SUSPICIOUS MODS"
        $lines += ("─" * 60)
        foreach ($mod in $suspiciousMods) {
            $lines += "  $($mod.FileName)  [Risk: $($mod.Risk)/100]"
            foreach ($p in $mod.Patterns) { $lines += "    PATTERN  $p" }
            foreach ($s in ($mod.Strings | Where-Object { $mod.Patterns -notcontains $_ })) { $lines += "    STRING   $s" }
        }
        $lines += ""
    }

    if ($bypassMods.Count -gt 0) {
        $lines += "BYPASS / INJECTION"
        $lines += ("─" * 60)
        foreach ($mod in $bypassMods) {
            $lines += "  $($mod.FileName)  [Risk: $($mod.Risk)/100]"
            foreach ($f in $mod.Flags) { $lines += "    $f" }
        }
        $lines += ""
    }

    if ($networkMods.Count -gt 0) {
        $lines += "NETWORK INDICATORS"
        $lines += ("─" * 60)
        foreach ($mod in $networkMods) {
            $lines += "  $($mod.FileName)  [Risk: $($mod.Risk)/100]"
            foreach ($i in $mod.Indicators) { $lines += "    $i" }
        }
        $lines += ""
    }

    try {
        $lines | Out-File -FilePath $logPath -Encoding UTF8 -ErrorAction Stop
        Blank
        Write-Host "  ✓  Report saved to:" -ForegroundColor Green
        Write-Host "     $logPath" -ForegroundColor White
    } catch {
        Write-Host "  ✗  Could not save: $_" -ForegroundColor Red
    }
}

# ── Footer ────────────────────────────────────────────────────────────────────
Blank
Rule "═" DarkCyan
Write-Host "  ✨  Analysis complete  ·  Pann Mod Check v2.0" -ForegroundColor Cyan
Rule "═" DarkCyan
Blank
Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
