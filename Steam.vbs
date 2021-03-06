On Error Resume Next

' 当前路径
Public FolderPath
' Steam 安装位置
Public SteamPath
' SteamApps 目录
Public SteamAppsPath
' Steam 游戏路径
Public SteamGamesPath
' Games.ini
Public SteamGamesINI

Const HKEY_CLASSES_ROOT  = &H80000000
Const HKEY_CURRENT_USER  = &H80000001
Const HKEY_LOCAL_MACHINE = &H80000002
Const HKEY_USERS         = &H80000003

Public strComputer
' 本地计算机
strComputer = "."

' ------------------------------------------------------------------------------------------------------------------------------------
Public OS: Set OS = GetOSInfos()

' 获取当前系统部分信息
Function GetOSInfos()
    Dim OS_: Set OS_ = CreateObject("Scripting.Dictionary")

    Dim ObjOS, O
    For Each ObjOS In GetObject("winmgmts:").InstancesOf("Win32_OperatingSystem")
        For Each O In ObjOS.Properties_
            OS_.Add O.Name, O.Value
        Next
    Next

    Dim rEx_OSv, regEx_OSv
    rEx_OSv = "(\d+)\.(\d+).*"
    Set regEx_OSv = New RegExp
    regEx_OSv.Pattern = rEx_OSv
    regEx_OSv.IgnoreCase = False
    regEx_OSv.Global = True

    OS_.Add "NT", regEx_OSv.Replace(OS_.Item("Version"), "$1$2")

    Dim rEx_OSa, regEx_OSa
    rEx_OSa = "\d+"
    Set regEx_OSa = New RegExp
    regEx_OSa.Pattern = rEx_OSa
    regEx_OSa.IgnoreCase = False
    regEx_OSa.Global = True

    Dim Matches, Match, Architecture
    Set Matches = regEx_OSa.Execute(OS_.Item("OSArchitecture"))
    For Each Match In Matches
        Architecture = Architecture & Match.Value
    Next

    If (Architecture = 32) Then Architecture = 86

    OS_.Add "Architecture", "x" & Architecture

    Set regEx_OSv = Nothing
    Set regEx_OSa = Nothing

    Set GetOSInfos = OS_
End Function

' ------------------------------------------------------------------------------------------------------------------------------------
If (OS.Item("NT") >= 60) Then
    If (WScript.Arguments.length = 0) Then
        ' 加“UAC”无用参数为跳出黑洞。。。
        CreateObject("Shell.Application").ShellExecute "wscript.exe", Chr(34)& WScript.ScriptFullName &Chr(34)& " UAC", "", "runas", 1
    Else
        Call Main() ' 以管理员权限执行之后代码
    End If
Else
    Call Main()
End If
' ------------------------------------------------------------------------------------------------------------------------------------


' ***********************************************
' * 入口函数
' ***********************************************
Function Main()
    Dim fso, WshShell, WshSysEnv, SystemRoot
    Set WshShell = CreateObject("WScript.Shell")
    Set WshSysEnv = WshShell.Environment("Process")
    Set fso = CreateObject("Scripting.FileSystemObject")

    SystemRoot = WshSysEnv.Item("SystemRoot")
    FolderPath = fso.GetParentFolderName(WScript.ScriptFullName)
    'FolderPath = Left(WScript.ScriptFullName,InstrRev(WScript.ScriptFullName,"\")-1)

    Dim result: Set result = CheckWindowsPath(FolderPath)
    If result.Item("status") = 300 Then
        ' MsgBox "安装路径正确，请耐心等待 Steam 客户端、服务部署完成...", 64, "提示信息"

        ' Steam 安装位置
        SteamPath       = FolderPath    & "\Steam"
        ' SteamApps 目录
        SteamAppsPath   = SteamPath     & "\SteamApps"
        ' Steam 游戏路径
        SteamGamesPath  = SteamAppsPath & "\common"
        ' Games.ini
        SteamGamesINI   = FolderPath    & "\Games.ini"

        ' 部署 Steam 客户端、服务、皮肤
        Call DeploySteam()

        ' 如果 Steam 游戏目录不存在则创建
        WshShell.Run "cmd.exe /C md " &Chr(34)& SteamGamesPath &Chr(34)& " >nul 2>nul", 0, True

        ' 获取、查找、联接 Steam 游戏
        Call GetSteamGames()

        ' 创建 Steam 桌面、开始菜单快捷方式
        Call PinItem(CreateShortcut(SteamPath & "\Steam.exe", "Steam", 0, "Desktop", 1, "", "", ""))
    Else
        MsgBox "当前路径 " &Chr(34)& FolderPath &Chr(34)& " 包含有非英文字符，请重新选择安装目录！", 16, "错误信息"

        Delete_Folder(SteamPath)
    End IF

    WScript.Sleep 300
    Delete_Folder( FolderPath & "\Tools" )
    Delete_Folder( FolderPath & "\Config" )
    Delete_File( FolderPath & "\make.vbs" )
    Delete_File( FolderPath & "\README.md" )
    Delete_File( SteamGamesINI )
    fso.DeleteFile WScript.ScriptFullName, True
End Function


' ***********************************************
' * 部署 Steam 客户端、服务、皮肤
' ***********************************************
Function DeploySteam()
    Dim SubKeyPathDel, SubKeyPath
    SubKeyPathDel = "Software\Valve"
    SubKeyPath = SubKeyPathDel & "\Steam"

    Dim ValueNames: Set ValueNames = CreateObject("Scripting.Dictionary")
    ValueNames.Add "Language",   "schinese"          ' Steam 客户端的语言
    ValueNames.Add "SkinV4",     "Metro for Steam"   ' Steam 客户端的皮肤 | http://metroforsteam.com

    ' 清空 Steam 注册表
    Call DeleteSubKeys(HKEY_CURRENT_USER, SubKeyPathDel)
    Call DeleteSubKeys(HKEY_LOCAL_MACHINE, SetRightRegNodePath(SubKeyPathDel, OS.Item("Architecture")))

    Call CreateRegKey(HKEY_CURRENT_USER, SubKeyPath)

    Dim ValueName
    For Each ValueName In ValueNames.Keys
        Call SetRegStringValue(HKEY_CURRENT_USER, SubKeyPath, ValueName, ValueNames.Item(ValueName))
    Next

    ' 释放 Steam 安装程序
    Dim Ext_7zip, Ext_Parameter1, Ext_Parameter2, Archives, Ext_Path

    Ext_7zip        = Chr(34)& FolderPath & "\Tools\7-Zip\" & OS.Item("Architecture") & "\7z.exe" &Chr(34)
    Ext_Parameter1  = " x "
    Archives        = Chr(34)& SteamPath & "\SteamSetup.exe" &Chr(34)
    Ext_Path        = " -o" &Chr(34)& SteamPath &Chr(34)
    Ext_Parameter2  = " *.exe *.txt -r -y"

    Dim WshShell: Set WshShell = CreateObject("WScript.Shell")

    ' 解压 Steam 安装包
    WshShell.Run Ext_7zip & Ext_Parameter1 & Archives & Ext_Path & Ext_Parameter2, 0, True
    ' 创建 Steam Client Service
    WshShell.Run Chr(34)& SteamPath & "\bin\SteamService.exe" &Chr(34)& " /install", 0, False
    ' 安装并打开 Steam 客户端
    WshShell.Run Chr(34)& SteamPath & "\Steam.exe" &Chr(34), 1, False

    Delete_File(Replace(Archives, Chr(34), ""))
End Function


' ***********************************************
' * 获取预置的 Steam 游戏
' ***********************************************
Function GetSteamGames()
    Dim INI: Set INI = (New INIFile)(SteamGamesINI)
    Dim Sections: Sections = INI.GetSections() ' array of section names

    If UBound(Sections) > -1 Then ' if there are no sections, the array is empty (UBound() = -1)
        Dim Section, Flag
        For Each Section In Sections
            Flag = False
            Dim Keys: Keys = INI.GetKeys(Section) ' array of a section's key names
            Dim Key
            For Each Key In Keys
                If Flag = False And RegExpTest("[^path\d+$]", Key, "") = False Then
                    Dim appid, installdir, path
                    appid = INI.GetValue(Section, "appid")
                    installdir = INI.GetValue(Section, "installdir")
                    path = INI.GetValue(Section, key)

                    Flag = SearchSteamGame(appid, installdir, path)
                End If
            Next
        Next
    Else
        MsgBox "INI File Is Empty", 48, "Notice:"
    End If
End Function

' ***********************************************
' * 查找 Steam 游戏
' ***********************************************
Function SearchSteamGame(appid, installdir, path)
    Const REMOVABLE_DRIVE = 2 ' Removable drive
    Const HARD_DISK       = 3 ' Local hard disk

    Dim Linked: Linked = False
    Dim fso, objWMIService, colDisks, objDisk
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")
    Set colDisks = objWMIService.ExecQuery("Select * from Win32_LogicalDisk where DriveType = " & HARD_DISK & "")

    Dim GamePath: GamePath = SteamGamesPath & "\" & installdir

    For Each objDisk In colDisks
        Dim BasePath, FullPath, ParentPath
        BasePath = objDisk.DeviceID & "\" & path
        FullPath = BasePath & "\" & installdir
        ParentPath = Left(BasePath, InstrRev(BasePath, "\")-1)

        If (Not fso.FolderExists(GamePath)) And fso.FolderExists(FullPath) Then
            Dim appmanifest: appmanifest = "appmanifest_" & appid & ".acf"

            If fso.FileExists(BasePath & "\" & appmanifest) Then
                fso.CopyFile BasePath & "\" & appmanifest, SteamAppsPath & "\"
            ElseIf fso.FileExists(ParentPath & "\" & appmanifest) Then
                fso.CopyFile ParentPath & "\" & appmanifest, SteamAppsPath & "\"
            End If

            Call CreateSteamGameLink(GamePath, FullPath)

            Linked = True

            Exit For
        End If
    Next

    SearchSteamGame = Linked
End Function

' *********************************************************
' * 联接 Steam 游戏
' ---------------------------------------------------------
' https://technet.microsoft.com/en-us/sysinternals/bb896768
' *********************************************************
Function CreateSteamGameLink(Link, Target)
    Dim WshShell, LinkTarget
    Set WshShell = CreateObject("WScript.Shell")
    LinkTarget = Chr(34)& Link &Chr(34)& " " &Chr(34)& Target &Chr(34)

    If (OS.Item("NT") >= 60) Then
        WshShell.Run "cmd.exe /C mklink /J " & LinkTarget, 0, True
    Else
        Dim Junction: Set Junction = CreateObject("Scripting.Dictionary")
        Junction.Add "x86", "junction.exe"
        Junction.Add "x64", "junction64.exe"

        Dim JunctionFile, Junction_Exe
        JunctionFile = Junction.Item(OS.Item("Architecture"))
        Junction_Exe = Chr(34)& FolderPath & "\Tools\Junction\" & JunctionFile &Chr(34)

        WshShell.Run Junction_Exe & " /accepteula", 0, True
        WshShell.Run Junction_Exe & " -nobanner " & LinkTarget, 0, True
    End If
End Function


' \/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
' ***********************************************
' * Pin to "anywhere" (^_^)
' ***********************************************
Function PinItem(App)
    Dim fso, objShell
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set objShell = CreateObject("Shell.Application")

    If Not fso.FileExists(App) Then Exit Function

    Dim AppPath, AppName
    AppPath = fso.GetParentFolderName(App)
    AppName = fso.GetFile(App).Name

    Dim objFolder, objFolderItem, colVerbs
    Set objFolder = objShell.NameSpace(AppPath)
    Set objFolderItem = objFolder.ParseName(AppName)
    Set colVerbs = objFolderItem.Verbs

    Dim objVerb, VerbName
    For Each objVerb In colVerbs
        VerbName = Replace(objVerb.name, "&", "")

        If VerbName = "固定到“开始”屏幕(P)" _
        Or VerbName = "Pin to Start" _
        Or VerbName = "附到「开始」菜单(U)" _
        Or VerbName = "Pin to Start Menu" Then objVerb.DoIt
    Next
End Function


' ***********************************************
' 创建 应用程序 快捷方式
' -----------------------------------------------
' Application   应用程序
' Name          快捷方式名
' Icon          图标
' Location      位置
' WindowStyle   运行方式
' Description   描述
' Arguments     参数
' Hotkey        快捷键
' ***********************************************
Function CreateShortcut(Application, Name, Icon, Location, WindowStyle, Arguments, Description, Hotkey)
    Dim WshShell, fso
    Set WshShell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")

    If Not fso.FileExists(Application) Then Exit Function

    Dim LocationFolder
    LocationFolder = Array("AllUsersDesktop", "AllUsersStartMenu", "AllUsersPrograms", "AllUsersStartup", "Desktop", "StartMenu", "Startup")
    For i=0 To UBound(LocationFolder)
        If LCase(Location) = LCase(LocationFolder(i)) Then
            Dim Shortcut_Path: Shortcut_Path = WshShell.SpecialFolders(LocationFolder(i))

            Exit For
        End If
    Next

    If Not fso.FolderExists(Shortcut_Path) Then Shortcut_Path = WshShell.SpecialFolders("Desktop")

    Dim Shortcut_Name, Shortcut_Extension, Shortcut_TargetPath, Shortcut_Icon
    Shortcut_Name        = Name
    Shortcut_Extension   = "lnk"
    Shortcut_TargetPath  = Application

    If IsNumeric(Icon) Then
        Shortcut_Icon    = Application & ", " & Icon
    Else
        Shortcut_Icon    = Icon
    End If

    Dim Shortcut_WorkingDir, Shortcut_WindowStyle, Shortcut_Description, Shortcut_Arguments, Shortcut_Hotkey, Shortcut_File
    Shortcut_WorkingDir  = fso.GetParentFolderName(Application)
    Shortcut_WindowStyle = WindowStyle
    Shortcut_Description = Description
    Shortcut_Arguments   = Arguments
    Shortcut_Hotkey      = Hotkey

    Shortcut_File = Shortcut_Path & "\" & Shortcut_Name & "." & Shortcut_Extension

    Dim lnk: Set lnk = WshShell.CreateShortcut(Shortcut_File)
    lnk.TargetPath       = Shortcut_TargetPath
    lnk.WindowStyle      = Shortcut_WindowStyle
    lnk.Description      = Shortcut_Description
    lnk.Arguments        = Shortcut_Arguments
    lnk.IconLocation     = Shortcut_Icon
    lnk.WorkingDirectory = Shortcut_WorkingDir

    ' IF LCase(Location) = "desktop" Or LCase(Location) = "startmenu" Then
    '     lnk.Hotkey       = Shortcut_Hotkey
    ' End If

    lnk.Save
    Set lnk = Nothing

    CreateShortcut = Shortcut_File
End Function


' ***********************************************
' * 一些实用的函数
' ***********************************************
' 删除指定的文件
Sub Delete_File(filespec)
    Dim fso: Set fso = CreateObject("Scripting.FileSystemObject")
    If (fso.FileExists(filespec)) Then fso.DeleteFile(filespec)
End Sub

' 删除指定的文件夹和其中的内容
Sub Delete_Folder(filespec)
    Dim fso: Set fso = CreateObject("Scripting.FileSystemObject")
    If (fso.FolderExists(filespec)) Then fso.DeleteFolder(filespec)
End Sub


' 设置注册表值: string
' https://msdn.microsoft.com/en-us/library/aa393600(v=vs.85).aspx
Function SetRegStringValue(RootKey, SubKeyPath, ValueName, Value)
    Dim objReg: Set objReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\default:StdRegProv")

    Return = objReg.SetStringValue(RootKey, SubKeyPath, ValueName, Value)

    If (Return <> 0) Or (Err.Number <> 0) Then
        MsgBox "SetStringValue failed. Error = " & Err.Number
    End If
End Function

' 创建注册表项
Function CreateRegKey(RootKey, SubKeyPath)
    Dim objReg: Set objReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\default:StdRegProv")

    Return = objReg.CreateKey(RootKey, SubKeyPath)

    If (Return <> 0) Or (Err.Number <> 0) Then
        MsgBox "CreateKey failed. Error = " & Err.Number
    End If
End Function

' 删除注册表项和所有子项
' https://technet.microsoft.com/en-us/magazine/2006.08.scriptingguy
Sub DeleteSubKeys(RootKey, SubKeyPath)
    Dim objReg, arrSubKeys, SubKey

    Set objReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & strComputer & "\root\default:StdRegProv")

    objReg.EnumKey RootKey, SubKeyPath, arrSubKeys

    If IsArray(arrSubKeys) Then
        For Each SubKey In arrSubKeys
            DeleteSubKeys RootKey, SubKeyPath & "\" & SubKey
        Next
    End If

    objReg.DeleteKey RootKey, SubKeyPath
End Sub


' 设置 x86, x64 正确的注册表节点
Function SetRightRegNodePath(SubKeyPath, OSArchitecture)
    Dim NodeName: Set NodeName = CreateObject("Scripting.Dictionary")
    NodeName.Add "x86", ""
    NodeName.Add "x64", "WOW6432Node"

    Dim StrNode: StrNode = NodeName.Item(OSArchitecture)
    IF (StrNode <> "") Then StrNode = "\" & StrNode

    Dim rEx_a, regEx_a
    rEx_a = "([A-Za-z]+)\\(\w+)(.*)"
    Set regEx_a = New RegExp
    regEx_a.Pattern = rEx_a
    regEx_a.IgnoreCase = False
    regEx_a.Global = False

    Dim rEx_b, regEx_b
    rEx_b = "WOW\d{4,}Node"
    Set regEx_b = New RegExp
    regEx_b.Pattern = rEx_b
    regEx_b.IgnoreCase = True
    regEx_b.Global = False

    Dim RetStr: RetStr = Split(regEx_a.Replace(SubKeyPath, "$1◆$2◆$3"), "◆")

    Dim a, b, c
    a = RetStr(0) : b = RetStr(1) : c = RetStr(2)

    IF (regEx_b.Replace(b, "") <> "") Then
        b = StrNode & "\" & b
    Else
        b = StrNode
    End If

    RetStr = a & b & c

    SetRightRegNodePath = RetStr
End Function


' 路径状态信息
Function CheckWindowsPathTips(d)
    Dim msg: msg = d.Item("string")

    If d.Item("status") = 300 Then
        msg = "正确：" & msg
    ElseIf d.Item("status") = 200 Then
        msg = "不能包含这些字符：" & msg
    ElseIf d.Item("status") = 100 Then
        msg = "磁盘驱动器错误：" & msg
    Else
        msg = "未知错误：" & msg
    End If

    CheckWindowsPathTips = msg
End Function


' 检测路径是否符合一定规范（非严格的）
Function CheckWindowsPath(Str)
    Dim rEx_h, rEx_b, rEx_s
    rEx_h = "((.*)(?:\:)\\?)(.*)"
    ' Windows 默认文件名不能包括的字符 \/:*?"<>|
    rEx_b = "[^`~!@#\$%\^&\(\)-\+=\[\]\{\};',\.\\\w\s]"
    rEx_s = "[A-Za-z]"

    Dim regEx_h: Set regEx_h = New RegExp
    regEx_h.Pattern = rEx_h
    regEx_h.IgnoreCase = False
    regEx_h.Global = True

    Dim regEx_b: Set regEx_b = New RegExp
    regEx_b.Pattern = rEx_b
    regEx_b.IgnoreCase = True
    regEx_b.Global = True

    Dim regEx_s: Set regEx_s = New RegExp
    regEx_s.Pattern = rEx_s
    regEx_s.IgnoreCase = False
    regEx_s.Global = False

    Dim t: Set t = CreateObject("Scripting.Dictionary")

    If regEx_h.Test(Str) Then
        ' https://msdn.microsoft.com/en-us/library/k9z80300(v=vs.84).aspx
        Dim RetStr: RetStr = Split(regEx_h.Replace(Str, "$1◆$2◆$3"), "◆")

        Dim a, b, c
        a = RetStr(0) : b = RetStr(1) : c = RetStr(2)

        If (Len(b) = 1) And regEx_s.Test(b) Then
            i = 0
            Dim Matches: Set Matches = regEx_b.Execute(c)
            Dim Match, s
            For Each Match In Matches
                If i = 0 Then
                    s = Match.Value
                Else
                    s = s & "," & Match.Value
                End If
                i = i + 1
            Next

            If (s = "") Then
                t.Add "status", 300
                t.Add "string", a & c
            Else
                t.Add "status", 200
                t.Add "string", s
            End If
        Else
            t.Add "status", 100
            t.Add "string", a
        End If
    Else
        t.Add "status", 0
        t.Add "string", Str
    End If

    Set CheckWindowsPath = t
End Function


' ***********************************************
' * 一个正则函数
' ***********************************************
Function RegExpTest(patrn, Str, ReStr)
    Dim regEx, Match, Matches   ' 创建变量
    Set regEx = New RegExp      ' 创建正则表达式
    regEx.Pattern = patrn       ' 设置模式
    regEx.IgnoreCase = True     ' 设置是否区分大小写
    regEx.Global = True         ' 设置全程匹配

    If (regEx.Test(Str) = True) Then
        If ReStr = "" Then
            Set Matches = regEx.Execute(Str)    ' 执行搜索
            For Each Match in Matches           ' 循环遍历 Matches 集合
                ' RetStr = RetStr & "偏移量 "
                ' RetStr = RetStr & Match.FirstIndex & "。" &vbCrLf& "字符：'"
                ' RetStr = RetStr & Match.Value & "'。" & vbCrLf
                RetStr = RetStr & Match.Value
            Next
        Else
            RetStr = regEx.Replace(Str, ReStr)
        End If
    Else
        RetStr = False
    End If

    RegExpTest = RetStr
End Function


' ---------------------------------------------------------------------------
' ***************************************************************************
' a VBScript class for reading from and writing to INI files.
' Usage: https://github.com/cparker15/INIFile.vbs
' ---------------------------------------------------------------------------
' INIFile.vbs: A VBScript class for reading from and writing to INI files.
' Copyright (C) 2004, 2011 Christopher Parker <http://www.cparker15.com/>
'
' INIFile.vbs is free software: you can redistribute it and/or modify
' it under the terms of the GNU Lesser General Public License as published by
' the Free Software Foundation, either version 3 of the License, or
' (at your option) any later version.
'
' INIFile.vbs is distributed in the hope that it will be useful,
' but WITHOUT ANY WARRANTY; without even the implied warranty of
' MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
' GNU Lesser General Public License for more details.
'
' You should have received a copy of the GNU Lesser General Public License
' along with INIFile.vbs.  If not, see <http://www.gnu.org/licenses/>.

' Option Explicit

Class INIFile
    Private FSO, FileName, FileContents

    ' Extract a key's value from its line in the INI file
    Private Function ExtractValue(ByVal MyFrom, ByVal MyStart, ByVal MyEnd)
        Dim PosS: PosS = InStr(1, MyFrom, MyStart, 1)

        If PosS > 0 Then
            PosS = PosS + Len(MyStart)
            Dim PosE: PosE = InStr(PosS, MyFrom, MyEnd, 1)
            If PosE = 0 Then PosE = InStr(PosS, MyFrom, vbCrLf, 1)
            If PosE = 0 Then PosE = Len(MyFrom) + 1
            ExtractValue = Mid(MyFrom, PosS, PosE - PosS)
        Else
            ExtractValue = vbNullString
        End If
    End Function

    Private Function GetFileContents()
        If Not FileExists() Then
            GetFileContents = vbNullString
        ElseIf FileIsEmpty() Then
            GetFileContents = vbNullString
        Else
            ' GetFileContents = FSO.OpenTextFile(FileName, ForReading).ReadAll

            Dim Stream: Set Stream = CreateObject("Adodb.Stream")
            Stream.Type = 2
            Stream.Mode = 3
            Stream.Charset = "UTF-8"
            Stream.Open
            Stream.LoadFromFile FileName
            GetFileContents = Stream.ReadText
            Stream.Close
            Set Stream = Nothing
        End If
    End Function

    Private Function GetSectionContents(MySection)
        Dim SectionContents: SectionContents = vbNullString
        Dim PosSection: PosSection = 0
        Dim PosEndSection: PosEndSection = 0

        ' Find [Section] specified.
        PosSection = InStr(1, FileContents, "[" & MySection & "]", vbTextCompare)

        If PosSection > 0 Then ' Section exists.
            PosEndSection = InStr(PosSection, FileContents, vbCrLf & "[") ' Find end of section.

            ' Is this last section? If so, mark the end of it as the end of the String (file's contents).
            If PosEndSection = 0 Then PosEndSection = Len(FileContents) + 1

            ' Separate section contents.
            SectionContents = Mid(FileContents, PosSection, PosEndSection - PosSection)
        End If

        GetSectionContents = SectionContents
    End Function

    ' Write contents to file, overwriting previous file contents. If the file doesn't already exist, it is created.
    Private Sub WriteFileContents(ByVal MyContents)
        Dim FileStream: Set FileStream = FSO.OpenTextFile(FileName, ForWriting, True)
        FileStream.Write MyContents
        FileStream.Close()
    End Sub

    Public Default Function Init(MyFileName)
        Set FSO  = CreateObject("Scripting.FileSystemObject")
        FileName = MyFileName

        Load

        Set Init = Me
    End Function

    Public Function GetFileName()
        GetFileName = Right(FileName, Len(FileName) - InStrRev(FileName, "\"))
    End Function

    Public Function GetFilePath()
        GetFilePath = Left(FileName, InStrRev(FileName, "\"))
    End Function

    Public Function FileExists()
        FileExists = FSO.FileExists(FileName)
    End Function

    Public Function FileIsEmpty()
        FileIsEmpty = FSO.OpenTextFile(FileName).AtEndOfStream
    End Function

    Public Function GetSections()
        Dim SectionsRegExp: Set SectionsRegExp = New RegExp

        ' Matches a [Section] on its own line. Could be at the very beginning of the file,
        ' in the middle of the file, or at the very end of the file (an empty [Section]).
        SectionsRegExp.Pattern = "([\r\n]\[|^\[)([^\]]*)(\][\r\n]|\]$)"

        ' Matches all occurrences, not just the first one.
        SectionsRegExp.Global = True

        Dim SectionMatches: Set SectionMatches = SectionsRegExp.Execute(FileContents)

        Dim Sections: Sections = Array()
        Dim Index

        If SectionMatches.Count > 0 Then
            For Index = 0 To SectionMatches.Count - 1
                ReDim Preserve Sections(Index)
                Sections(Index) = SectionMatches.Item(Index).SubMatches(1)
            Next
        End If

        GetSections = Sections
    End Function

    Public Function GetKeys(MySection)
        ' Grab the contents of the specified [Section]
        Dim SectionContents: SectionContents = GetSectionContents(MySection)

        Dim KeysRegExp: Set KeysRegExp = New RegExp

        ' Matches a key= on its own line; captures the name of the key.
        KeysRegExp.Pattern = "[\r\n]{1,2}([^=]*)="

        ' Matches all occurrences, not just the first one.
        KeysRegExp.Global = True

        Dim KeyMatches: Set KeyMatches = KeysRegExp.Execute(SectionContents)

        Dim Keys: Keys = Array()
        Dim Index

        If KeyMatches.Count > 0 Then
            For Index = 0 To KeyMatches.Count - 1
                ReDim Preserve Keys(Index)
                Keys(Index) = KeyMatches.Item(Index).SubMatches(0)
            Next
        End If

        GetKeys = Keys
    End Function

    Public Function GetValue(MySection, MyKeyName)
        Dim Value

        ' Grab the contents of the specified [Section]
        Dim SectionContents: SectionContents = GetSectionContents(MySection)

        ' Look for the key=
        If InStr(1, SectionContents, vbCrLf & MyKeyName & "=", vbTextCompare) > 0 Then
            ' Extract the value from the key= line.
            Value = ExtractValue(SectionContents, vbCrLf & MyKeyName & "=", vbCrLf)
        End If

        GetValue = Value
    End Function

    ' Unlike Dictionary's Add() method, SetValue() can change the value of an existing key.
    Public Sub SetValue(MySection, MyKeyName, MyValue)
        ' Grab the contents of the specified [Section]
        Dim OldSectionContents: OldSectionContents = GetSectionContents(MySection)

        If OldSectionContents <> vbNullString Then ' Section exists.
            Dim KeyName, Line, Found, NewSectionContents

            OldSectionContents = Split(OldSectionContents, vbCrLf)
            KeyName = LCase(MyKeyName & "=") ' Temp variable to find a key.

            ' Copy each line over; if the key matches, change its value first.
            For Each Line In OldSectionContents
                If LCase(Left(Line, Len(KeyName))) = KeyName Then
                    Line = KeyName & MyValue
                    Found = True
                End If

                NewSectionContents = NewSectionContents & Line & vbCrLf
            Next

            If IsEmpty(Found) Then ' Key not found.
                ' Append it to the [Section].
                NewSectionContents = NewSectionContents & KeyName & MyValue
            Else ' Key found.
                ' Remove last vbCrLf. There's already a vbCrLf at the end of the [Section].
                NewSectionContents = Left(NewSectionContents, Len(NewSectionContents) - 2)
            End If

            ' Combine pre-section, new section, and post-section data.
            FileContents = Left(FileContents, PosSection-1) & NewSectionContents & Mid(FileContents, PosEndSection)
        Else ' Section doesn't exist.
            ' If the file doesn't already end in a new line, and if the file isn't empty...
            If Right(FileContents, 2) <> vbCrLf And Len(FileContents) > 0 Then
                ' Add a new line to the end of the file
                FileContents = FileContents & vbCrLf
            End If

            ' Add section data at the end of file contents.
            FileContents = FileContents & "[" & MySection & "]" & vbCrLf & MyKeyName & "=" & MyValue
        End If ' If OldSectionContents <> vbNullString Then
    End Sub

    Public Sub Load
        FileContents = GetFileContents
    End Sub

    Public Sub Save
        WriteFileContents(FileContents)
    End Sub
End Class
