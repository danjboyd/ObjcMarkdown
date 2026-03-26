Option Explicit

Function Quote(argument)
  Quote = """" & Replace(argument, """", """""") & """"
End Function

Dim shell, fso, root, command, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
command = Quote(fso.BuildPath(root, "MarkdownViewer-dev.cmd"))

For i = 0 To WScript.Arguments.Count - 1
  command = command & " " & Quote(WScript.Arguments(i))
Next

shell.Run command, 0, False
