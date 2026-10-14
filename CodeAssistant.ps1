<#
.SYNOPSIS
    Real-Time Interactive AI Code ChatBot with Ollama & PowerShell.

.DESCRIPTION
    Launches a persistent, continuous multi-turn chat session with Ollama in your PowerShell console.
    Features:
    - Real-time token-by-token streaming output directly into the console.
    - Full multi-turn conversation memory (the bot remembers previous questions & answers).
    - Optional GUI popup for drafting multi-line instructions (:gui).
    - Commands: :save (applies code changes with automatic backup), :clear (resets chat), :gui (opens popup), :exit (quits).

.PARAMETER TargetPath
    Path to the source file or directory for code context. Defaults to current directory.

.PARAMETER Model
    The Ollama model to use. Defaults to "qwen2.5-coder:latest" or the first installed model.
#>

param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$TargetPath = ".",

    [Parameter(Mandatory = $false)]
    [string]$Model = "qwen2.5-coder:latest",

    [Parameter(Mandatory = $false)]
    [string]$OllamaUrl = "http://localhost:11434"
)

# Enforce UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Load required .NET assemblies for Windows PowerShell (5.1 & Core compatible)
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

# Verify target path
$ResolvedTarget = Resolve-Path -Path $TargetPath -ErrorAction SilentlyContinue
if (-not $ResolvedTarget) {
    Write-Host "[!] Target path not found: $TargetPath" -ForegroundColor Red
    exit 1
}

$IsFile = Test-Path -Path $ResolvedTarget.Path -PathType Leaf
$TargetContent = ""

if ($IsFile) {
    $TargetContent = Get-Content -Path $ResolvedTarget.Path -Raw -ErrorAction SilentlyContinue
    $LineCount = ($TargetContent -split "`n").Count
    Write-Host "[+] Loaded Target File: $($ResolvedTarget.Path) ($LineCount lines)" -ForegroundColor Cyan
} else {
    Write-Host "[+] Loaded Directory: $($ResolvedTarget.Path)" -ForegroundColor Cyan
    $Files = Get-ChildItem -Path $ResolvedTarget.Path -Recurse -File | 
             Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|venv|__pycache__)\\' } | 
             Select-Object -First 30
    $FileSummaries = @()
    foreach ($f in $Files) {
        $FileSummaries += "File: $($f.FullName)`n" + (Get-Content $f.FullName -TotalCount 15 -ErrorAction SilentlyContinue -Raw)
    }
    $TargetContent = $FileSummaries -join "`n`n---`n`n"
}

# Check Ollama Connectivity & Detect Models
Write-Host "[*] Checking Ollama at $OllamaUrl..." -ForegroundColor DarkGray
$AvailableModels = @()
try {
    $TagsResponse = Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop
    if ($TagsResponse.models -and $TagsResponse.models.Count -gt 0) {
        $AvailableModels = @($TagsResponse.models | ForEach-Object { $_.name })
    }
} catch {
    Write-Host "[!] Warning: Could not connect to Ollama at $OllamaUrl." -ForegroundColor Yellow
    Write-Host "    Make sure Ollama is running ('ollama serve')." -ForegroundColor Yellow
}

if ($AvailableModels.Count -eq 0) {
    Write-Host "`n[!] WARNING: No models are installed in Ollama yet!" -ForegroundColor Red
    Write-Host "    Please run in another PowerShell window: ollama pull qwen2.5-coder:1.5b" -ForegroundColor Yellow
    Write-Host "    Or standard model:                       ollama pull qwen2.5-coder:7b`n" -ForegroundColor Yellow
    $ActiveModel = $Model
} elseif ($AvailableModels -contains $Model) {
    $ActiveModel = $Model
} else {
    $ActiveModel = $AvailableModels[0]
}

# Function to launch WPF Popup for drafting multi-line prompts
function Show-PromptPopup {
    param([string]$InitialText = "")

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Assistant - Draft Prompt" Height="380" Width="580"
        WindowStartupLocation="CenterScreen" Background="#1E1E2E" ResizeMode="CanResizeWithGrip">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Write Your Prompt / Instructions (Ctrl+Enter to Send):" 
                   FontSize="14" FontWeight="SemiBold" Foreground="#CDD6F4" Margin="0,0,0,10"/>

        <Border Grid.Row="1" CornerRadius="6" Background="#181825" BorderBrush="#45475A" BorderThickness="1" Margin="0,0,0,12">
            <TextBox Name="TxtInput" TextWrapping="Wrap" AcceptsReturn="True" AcceptsTab="True"
                     VerticalScrollBarVisibility="Auto" Background="Transparent" Foreground="#CDD6F4"
                     CaretBrush="#89B4FA" FontSize="13" Padding="8" BorderThickness="0"/>
        </Border>

        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBlock Grid.Column="0" Text="Ctrl+Enter to send" Foreground="#6C7086" VerticalAlignment="Center" FontSize="11"/>
            <Button Grid.Column="1" Name="BtnCancel" Content="Cancel" Width="75" Height="28" Margin="0,0,8,0"
                    Background="#313244" Foreground="#CDD6F4" BorderThickness="0" Cursor="Hand"/>
            <Button Grid.Column="2" Name="BtnSend" Content="Send" Width="100" Height="28"
                    Background="#89B4FA" Foreground="#11111B" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

    $StringReader = New-Object System.IO.StringReader($xaml)
    $XmlReader = [System.Xml.XmlReader]::Create($StringReader)
    $Win = [System.Windows.Markup.XamlReader]::Load($XmlReader)

    $TxtInput = $Win.FindName("TxtInput")
    $BtnSend = $Win.FindName("BtnSend")
    $BtnCancel = $Win.FindName("BtnCancel")

    $TxtInput.Text = $InitialText
    $TxtInput.Focus()

    $ResultText = ""
    $BtnSend.Add_Click({
        $Script:ResultText = $TxtInput.Text
        $Win.Close()
    })
    $BtnCancel.Add_Click({
        $Win.Close()
    })
    $TxtInput.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            $Script:ResultText = $TxtInput.Text
            $Win.Close()
        }
    })

    $null = $Win.ShowDialog()
    return $Script:ResultText
}

# Real-Time Token Streaming via HttpClient
function Send-ChatStreaming {
    param(
        [string]$Url,
        [string]$ModelName,
        [array]$Messages
    )

    $ChatPayload = @{
        model = $ModelName
        messages = $Messages
        stream = $true
    } | ConvertTo-Json -Depth 10

    $HttpClient = [System.Net.Http.HttpClient]::new()
    $HttpClient.Timeout = [System.TimeSpan]::FromMinutes(10)
    $Content = [System.Net.Http.StringContent]::new($ChatPayload, [System.Text.Encoding]::UTF8, "application/json")

    $FullReply = New-Object System.Text.StringBuilder

    try {
        $HttpRequest = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, "$Url/api/chat")
        $HttpRequest.Content = $Content
        $Response = $HttpClient.SendAsync($HttpRequest, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        
        if (-not $Response.IsSuccessStatusCode) {
            $ErrBody = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            Write-Host "`n[!] Ollama HTTP Error: $($Response.StatusCode) - $ErrBody" -ForegroundColor Red
            return $null
        }

        $Stream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::UTF8)

        while (-not $Reader.EndOfStream) {
            $Line = $Reader.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($Line)) {
                try {
                    $TokenObj = $Line | ConvertFrom-Json
                    if ($TokenObj.message.content) {
                        Write-Host -NoNewline $TokenObj.message.content -ForegroundColor White
                        [void]$FullReply.Append($TokenObj.message.content)
                    }
                } catch {}
            }
        }
        $Reader.Dispose()
        $Stream.Dispose()
    } catch {
        Write-Host "`n[!] Connection Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    } finally {
        if ($HttpClient) {
            $HttpClient.Dispose()
        }
    }

    Write-Host "" # New line after stream ends
    return $FullReply.ToString()
}

# Function to save extracted code block to target file
function Save-CodeChanges {
    param(
        [string]$LastResponse,
        [string]$FilePath
    )

    if (-not $IsFile) {
        Write-Host "[!] Target is a directory. Specify an exact file to overwrite." -ForegroundColor Yellow
        return
    }

    $RegexPattern = '(?s)```(?:\w+)?\r?\n(.*?)\r?\n```'
    $Matches = [regex]::Matches($LastResponse, $RegexPattern)

    if ($Matches.Count -eq 0) {
        Write-Host "[!] No markdown code blocks found in the last response to save." -ForegroundColor Yellow
        return
    }

    $CodeToSave = $Matches[0].Groups[1].Value

    # Create backup copy
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupPath = "$FilePath.bak_$Timestamp"
    Copy-Item -Path $FilePath -Destination $BackupPath -Force
    Write-Host "[+] Backup created: $BackupPath" -ForegroundColor Green

    Set-Content -Path $FilePath -Value $CodeToSave -Encoding UTF8
    Write-Host "[+] Successfully saved latest code to: $FilePath" -ForegroundColor Green
}

# Initialize Conversation State
$SystemMessage = @"
You are an expert AI code reviewer, software architect, and pair programmer.
The user is working with code in PowerShell.
Always provide defensive, production-ready, clean solutions.
When suggesting code fixes, format code in standard markdown code blocks (```language ... ```).
"@

$Fence = '```'
$InitialContext = @"
CURRENT TARGET: $($ResolvedTarget.Path)

CONTEXT:
$Fence
$TargetContent
$Fence
"@

$Conversation = [System.Collections.Generic.List[hashtable]]::new()
$Conversation.Add(@{ role = "system"; content = $SystemMessage })
$Conversation.Add(@{ role = "user"; content = "Here is the code context I am working on:`n$InitialContext`n`nPlease acknowledge and give a 2-sentence summary of what this code does." })

# Header Banner
Write-Host "`n==================================================================" -ForegroundColor Magenta
Write-Host " 🤖 OLLAMA REAL-TIME CODE CHATBOT (POWERED BY POWERSHELL)" -ForegroundColor Cyan
Write-Host " [*] Active Model: $ActiveModel" -ForegroundColor Green
Write-Host " [*] Target:       $($ResolvedTarget.Path)" -ForegroundColor White
Write-Host "==================================================================" -ForegroundColor Magenta
Write-Host " Commands available at any time:" -ForegroundColor DarkGray
Write-Host "   :gui    - Open multi-line popup window to write long instructions" -ForegroundColor DarkCyan
Write-Host "   :save   - Apply & overwrite the latest code suggestion to the file" -ForegroundColor DarkCyan
Write-Host "   :clear  - Clear conversation history and reload target code" -ForegroundColor DarkCyan
Write-Host "   :model  - Switch active Ollama model" -ForegroundColor DarkCyan
Write-Host "   :exit   - Exit chatbot (or type 'exit')" -ForegroundColor DarkCyan
Write-Host "==================================================================`n" -ForegroundColor Magenta

# Initial greeting / acknowledgment
Write-Host "[Assistant] > " -NoNewline -ForegroundColor Green
$InitialAck = Send-ChatStreaming -Url $OllamaUrl -ModelName $ActiveModel -Messages $Conversation
if ($InitialAck) {
    $Conversation.Add(@{ role = "assistant"; content = $InitialAck })
}

$LastAssistantResponse = $InitialAck

# Main Real-Time Conversation Loop
while ($true) {
    Write-Host "`n[You] > " -NoNewline -ForegroundColor Cyan
    $UserInput = [Console]::ReadLine()

    if ([string]::IsNullOrWhiteSpace($UserInput)) {
        continue
    }

    # Handle Commands
    if ($UserInput -match "^:(exit|quit)$" -or $UserInput -eq "exit" -or $UserInput -eq "quit") {
        Write-Host "[*] Exiting AI Assistant. Happy coding!" -ForegroundColor Yellow
        break
    }

    if ($UserInput -eq ":save") {
        Save-CodeChanges -LastResponse $LastAssistantResponse -FilePath $ResolvedTarget.Path
        continue
    }

    if ($UserInput -eq ":clear") {
        $Conversation.Clear()
        $Conversation.Add(@{ role = "system"; content = $SystemMessage })
        $Conversation.Add(@{ role = "user"; content = "Here is the code context I am working on:`n$InitialContext`n`nPlease acknowledge." })
        Write-Host "[*] Conversation cleared and code context reloaded." -ForegroundColor Yellow
        continue
    }

    if ($UserInput -eq ":gui" -or $UserInput -eq ":popup") {
        Write-Host "[*] Opening GUI prompt window..." -ForegroundColor DarkGray
        $PopupText = Show-PromptPopup -InitialText ""
        if ([string]::IsNullOrWhiteSpace($PopupText)) {
            Write-Host "[*] Popup cancelled or empty." -ForegroundColor Yellow
            continue
        }
        $UserInput = $PopupText
        Write-Host "[Prompt from GUI]: $UserInput" -ForegroundColor Cyan
    }

    if ($UserInput -match "^:model\s*(.*)$") {
        $NewModel = $Matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($NewModel)) {
            Write-Host "[*] Available models: $($AvailableModels -join ', ')" -ForegroundColor Cyan
            Write-Host "[*] Current model: $ActiveModel" -ForegroundColor White
            $NewModel = Read-Host "Enter model name to switch to"
        }
        if (-not [string]::IsNullOrWhiteSpace($NewModel)) {
            $ActiveModel = $NewModel
            Write-Host "[+] Switched active model to: $ActiveModel" -ForegroundColor Green
        }
        continue
    }

    # Add message to history
    $Conversation.Add(@{ role = "user"; content = $UserInput })

    # Stream the assistant's reply in real-time
    Write-Host "`n[Assistant] > " -NoNewline -ForegroundColor Green
    $AssistantReply = Send-ChatStreaming -Url $OllamaUrl -ModelName $ActiveModel -Messages $Conversation

    if ($AssistantReply) {
        $Conversation.Add(@{ role = "assistant"; content = $AssistantReply })
        $LastAssistantResponse = $AssistantReply

        # Check if code block was returned
        if ($IsFile -and $AssistantReply -match '(?s)```(?:\w+)?\r?\n(.*?)\r?\n```') {
            Write-Host "`n💡 Tip: Type ':save' to overwrite $($ResolvedTarget.Path) with this code (auto-backed up)." -ForegroundColor DarkYellow
        }
    }
}
