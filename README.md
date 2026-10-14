# 🤖 Real-Time AI Code ChatBot (Ollama & PowerShell)

An interactive, continuous multi-turn code assistant that runs directly in your PowerShell terminal with live token streaming, context memory, and safe file patching.

---

## ⚡ What's New: Full Real-Time Chat Mode
- **Never shuts down after one message**: Stays alive in an interactive conversation loop (`[You] >`).
- **Live Token Streaming**: Code and answers appear character-by-character in real-time as Ollama generates them.
- **Full Conversation Memory**: Remembers your previous questions, code changes, and instructions throughout the session.
- **On-Demand GUI Popup**: Type `:gui` at any prompt to draft long instructions in a dark-mode window.
- **Safe Instant Patching**: Type `:save` to automatically overwrite your target file with the latest code suggestion after creating a `.bak` backup.

---

## 🛠️ In-Chat Commands

| Command | Action |
|---|---|
| *(Type anything)* | Talk to the AI, ask follow-up questions, request changes |
| `:gui` or `:popup` | Opens the graphical multi-line editor to draft a long prompt |
| `:save` | Overwrites the target file with the latest code block (creates a timestamped backup first) |
| `:clear` | Clears conversation memory and reloads the file |
| `:model` | Switch the active Ollama model without restarting |
| `:exit` or `exit` | Quits the chatbot session |

---

## 🚀 How to Run

1. **Make sure your model is pulled in Ollama**:
   ```powershell
   ollama pull qwen2.5-coder:1.5b
   ```

2. **Start the ChatBot**:
   ```powershell
   Set-Location "C:\Users\wwwam\OneDrive\Desktop\hacking execution"
   .\CodeAssistant.ps1 -TargetPath .\sample_server.py
   ```

3. **Or run from anywhere using the full path**:
   ```powershell
   & "C:\Users\wwwam\OneDrive\Desktop\hacking execution\CodeAssistant.ps1" -TargetPath "C:\Users\wwwam\OneDrive\Desktop\hacking execution\sample_server.py"
   ```
