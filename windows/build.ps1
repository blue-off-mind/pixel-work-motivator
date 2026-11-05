# Windows 构建脚本（上班激励器）
# 用法：
#   .\build.ps1 test       - 运行计算核心单元测试（17 组用例）
#   .\build.ps1 build      - 编译应用
#   .\build.ps1 run        - 编译并启动
#   .\build.ps1 publish    - 编译单文件自包含 exe（输出至 windows\publish）
#   .\build.ps1 clean      - 清理构建产物

param (
    [string]$Action = "build"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 优先使用 D:\dotnet，如果没有则使用 PATH 中的 dotnet
if (Test-Path "D:\dotnet\dotnet.exe") {
    $Dotnet = "D:\dotnet\dotnet.exe"
} else {
    $Dotnet = (Get-Command dotnet).Source
}

$env:NUGET_PACKAGES = "D:\.nuget\packages"
$env:TEMP = "D:\temp"
$env:TMP = "D:\temp"
if (Test-Path "D:\dotnet") { $env:DOTNET_ROOT = "D:\dotnet" }
if (!(Test-Path "D:\temp")) { New-Item -ItemType Directory -Path "D:\temp" -Force | Out-Null }

Write-Host "使用 .NET SDK: $Dotnet" -ForegroundColor Cyan

switch ($Action.ToLower()) {
    "test" {
        Write-Host "==> 运行计算核心单元测试..." -ForegroundColor Yellow
        & $Dotnet run --project "$ScriptDir\Tests\Tests.csproj"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "build" {
        Write-Host "==> 编译应用 (Debug)..." -ForegroundColor Yellow
        & $Dotnet build "$ScriptDir\PixelWorkMotivator\PixelWorkMotivator.csproj"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    "run" {
        Write-Host "==> 启动应用..." -ForegroundColor Yellow
        & $Dotnet run --project "$ScriptDir\PixelWorkMotivator\PixelWorkMotivator.csproj"
    }
    "publish" {
        Write-Host "==> 发布独立应用 (win-x64)..." -ForegroundColor Yellow
        $OutDir = "$ScriptDir\publish"
        & $Dotnet publish "$ScriptDir\PixelWorkMotivator\PixelWorkMotivator.csproj" `
            -c Release `
            -r win-x64 `
            --self-contained true `
            -p:PublishSingleFile=true `
            -o $OutDir

        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "`n✓ 发布完成！可执行文件路径: $OutDir\PixelWorkMotivator.exe" -ForegroundColor Green
    }
    "clean" {
        Write-Host "==> 清理构建产物..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force "$ScriptDir\PixelWorkMotivator\bin" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$ScriptDir\PixelWorkMotivator\obj" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$ScriptDir\Tests\bin" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$ScriptDir\Tests\obj" -ErrorAction SilentlyContinue
        Write-Host "✓ 清理完成" -ForegroundColor Green
    }
    default {
        Write-Host "未知指令: $Action" -ForegroundColor Red
        Write-Host "支持的指令: test, build, run, publish, clean"
        exit 1
    }
}
