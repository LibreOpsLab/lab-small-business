@{
    # The lab's Windows tuning profile: what to switch off, tighten, or remove, and WHY.
    # Optimize-Windows.ps1 reads this file. Edit the profile, not the script: every line is a
    # decision a reviewer can read, argue with, and take out. See docs/WindowsTuning.md.
    #
    # Each item has:
    #   Type   Registry | Service | Task | Feature | Appx | AuditPol | Hibernate
    #   Roles  Client, Server, or Both (Client = Windows 11, Server = Windows Server)
    #   Why    one line for the student: the reason, and the trade-off if there is one
    #
    # Deliberately NOT here: Windows Update, Defender, the firewall, Credential Guard / VBS
    # (they conflict with nested virtualisation and are the course's security baseline), and
    # anything in ProtectedServices below.
    Version           = 1

    ProtectedServices = @(
        'wuauserv', 'UsoSvc', 'BITS', 'WinDefend', 'WdNisSvc', 'mpssvc', 'BFE', 'EventLog',
        'Dnscache', 'Dhcp', 'LanmanWorkstation', 'LanmanServer', 'W32Time', 'Netlogon',
        'RpcSs', 'RpcEptMapper', 'DcomLaunch', 'Winmgmt', 'CryptSvc', 'Schedule', 'WinRM',
        'TrustedInstaller', 'Appinfo', 'KeyIso', 'SamSs', 'lsass', 'gpsvc', 'ProfSvc', 'nsi'
    )

    Categories        = @(

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Telemetry'
            Description = 'Stop Windows sending diagnostic and usage data to Microsoft.'
            Items       = @(
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Kind = 'DWord'
                   Why = 'Diagnostic data level 0 (Security). Honoured on Enterprise, Education and Server only; on Pro it is treated as the minimum (Required).' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Value = 1; Kind = 'DWord'
                   Why = 'No "How is Windows?" feedback prompts.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowDeviceNameInTelemetry'; Value = 0; Kind = 'DWord'
                   Why = 'Do not attach the computer name to diagnostic data.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection'; Value = 1; Kind = 'DWord'
                   Why = 'Do not upload diagnostic logs on request.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDumpCollection'; Value = 1; Kind = 'DWord'
                   Why = 'Do not upload memory dumps. A dump can contain passwords and documents.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableOneSettingsDownloads'; Value = 1; Kind = 'DWord'
                   Why = 'Stop Windows fetching remote configuration from Microsoft.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Value = 1; Kind = 'DWord'
                   Why = 'No crash reports sent to Microsoft. Trade-off: you read the local Event Log instead.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable'; Value = 0; Kind = 'DWord'
                   Why = 'Customer Experience Improvement Program off.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Value = 0; Kind = 'DWord'
                   Why = 'Application Impact Telemetry off.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Value = 1; Kind = 'DWord'
                   Why = 'No inventory of installed software sent to Microsoft.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableUAR'; Value = 1; Kind = 'DWord'
                   Why = 'Steps Recorder off. It records what a user does on screen.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Value = 1; Kind = 'DWord'
                   Why = 'No advertising ID for tracking across apps.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Value = 0; Kind = 'DWord'
                   Why = 'Activity history (Timeline) off.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0; Kind = 'DWord'
                   Why = 'Do not record what the user opens.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Value = 0; Kind = 'DWord'
                   Why = 'Do not upload activity history.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; Name = 'DisableLocation'; Value = 1; Kind = 'DWord'
                   Why = 'Location services off. A server has no use for them.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'DiagTrack'; StartupType = 'Disabled'
                   Why = 'Connected User Experiences and Telemetry: the service that sends the data.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'dmwappushservice'; StartupType = 'Disabled'
                   Why = 'WAP push routing used by telemetry and device management. Not needed for a domain lab.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'WerSvc'; StartupType = 'Disabled'
                   Why = 'Windows Error Reporting service.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser'
                   Why = 'Scans the machine and reports software inventory.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater'
                   Why = 'Collects program telemetry.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator'
                   Why = 'CEIP data upload.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip'
                   Why = 'CEIP data for USB devices.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector'
                   Why = 'Uploads disk diagnostic data.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClient'
                   Why = 'Feedback client.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClientOnScenarioDownload'
                   Why = 'Feedback client.' }
                @{ Type = 'Task'; Roles = 'Both'; Path = '\Microsoft\Windows\Windows Error Reporting\'; Name = 'QueueReporting'
                   Why = 'Sends queued error reports.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Consumer features'
            Description = 'Remove the advertising, suggestions and cloud features of a consumer PC.'
            Items       = @(
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Kind = 'DWord'
                   Why = 'Stops Windows installing suggested apps (the games and trial software that appear after sign-in). Honoured on Enterprise and Education.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlightFeatures'; Value = 1; Kind = 'DWord'
                   Why = 'No Spotlight lock-screen and desktop suggestions.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableCloudOptimizedContent'; Value = 1; Kind = 'DWord'
                   Why = 'No cloud-delivered content in the shell.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0; Kind = 'DWord'
                   Why = 'Cortana off.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Value = 1; Kind = 'DWord'
                   Why = 'Start search stays local: what you type is not sent to Bing.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Value = 0; Kind = 'DWord'
                   Why = 'No web results in search.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Value = 0; Kind = 'DWord'
                   Why = 'Widgets and news feed off. They use memory and network.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Kind = 'DWord'
                   Why = 'Copilot off. Sends what you ask to a cloud service.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1; Kind = 'DWord'
                   Why = 'Recall off: no screenshots of everything you do kept on disk.' }
                @{ Type = 'Registry'; Roles = 'Client'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSyncNGSC'; Value = 1; Kind = 'DWord'
                   Why = 'OneDrive sync off. The lab uses its own file server and NextCloud.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Name = 'LetAppsRunInBackground'; Value = 2; Kind = 'DWord'
                   Why = 'Apps cannot run in the background (2 = force deny). Saves CPU, memory and battery.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Value = 0; Kind = 'DWord'
                   Why = 'Delivery Optimization: HTTP only, no peer-to-peer sharing of updates with other PCs. Updates still install.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Value = 0; Kind = 'DWord'
                   Why = 'Edge does not preload at sign-in.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'BackgroundModeEnabled'; Value = 0; Kind = 'DWord'
                   Why = 'Edge does not keep running after you close it.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled'; Value = 0; Kind = 'DWord'
                   Why = 'Edge sidebar (and its Copilot/shopping) off.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Apps'
            Description = 'Remove built-in apps nobody in the lab needs. An explicit list: nothing is removed by wildcard.'
            Items       = @(
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.BingNews'; Why = 'News feed app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.BingWeather'; Why = 'Weather app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.BingSearch'; Why = 'Bing search integration.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.GetHelp'; Why = 'Get Help app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.Getstarted'; Why = 'Tips app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.MicrosoftOfficeHub'; Why = 'Microsoft 365 advert hub.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.MicrosoftSolitaireCollection'; Why = 'Games.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.MixedReality.Portal'; Why = 'Mixed Reality Portal. No headsets in the lab.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.People'; Why = 'People app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.PowerAutomateDesktop'; Why = 'Power Automate Desktop.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.Todos'; Why = 'To Do.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.WindowsFeedbackHub'; Why = 'Feedback Hub. Pairs with the telemetry settings.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.ZuneMusic'; Why = 'Media Player / Groove.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.ZuneVideo'; Why = 'Movies and TV.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.YourPhone'; Why = 'Phone Link.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Clipchamp.Clipchamp'; Why = 'Video editor.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.Xbox.TCUI'; Why = 'Xbox components.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.XboxGamingOverlay'; Why = 'Xbox Game Bar.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.XboxIdentityProvider'; Why = 'Xbox sign-in.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.XboxSpeechToTextOverlay'; Why = 'Xbox overlay.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.GamingApp'; Why = 'Xbox app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.OutlookForWindows'; Why = 'The new Outlook. The lab uses Betterbird against its own mail server.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'Microsoft.Copilot'; Why = 'Copilot app.' }
                @{ Type = 'Appx'; Roles = 'Client'; Name = 'MicrosoftCorporationII.QuickAssist'; Why = 'Quick Assist remote support: remote access you did not choose to enable.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Services'
            Description = 'Switch off services this lab does not use. Each is a running program and a possible way in.'
            Items       = @(
                @{ Type = 'Service'; Roles = 'Server'; Name = 'Spooler'; StartupType = 'Disabled'
                   Why = 'Print Spooler on a server that does not print. It was the target of PrintNightmare and a regular source of privilege-escalation bugs.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'RemoteRegistry'; StartupType = 'Disabled'
                   Why = 'Lets remote users read the registry. Disabled by default; this keeps it that way.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'SSDPSRV'; StartupType = 'Disabled'
                   Why = 'SSDP discovery: announces and finds devices (UPnP) on the network.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'upnphost'; StartupType = 'Disabled'
                   Why = 'UPnP device host.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'lfsvc'; StartupType = 'Disabled'
                   Why = 'Geolocation service.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'MapsBroker'; StartupType = 'Disabled'
                   Why = 'Downloaded Maps Manager.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'RetailDemo'; StartupType = 'Disabled'
                   Why = 'Retail demo mode.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'WMPNetworkSvc'; StartupType = 'Disabled'
                   Why = 'Windows Media Player network sharing.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'Fax'; StartupType = 'Disabled'
                   Why = 'Fax.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'PhoneSvc'; StartupType = 'Disabled'
                   Why = 'Phone service for Phone Link.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'icssvc'; StartupType = 'Disabled'
                   Why = 'Mobile hotspot: turns the PC into a network access point.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'XblAuthManager'; StartupType = 'Disabled'
                   Why = 'Xbox Live authentication.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'XblGameSave'; StartupType = 'Disabled'
                   Why = 'Xbox cloud saves.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'XboxNetApiSvc'; StartupType = 'Disabled'
                   Why = 'Xbox networking.' }
                @{ Type = 'Service'; Roles = 'Client'; Name = 'XboxGipSvc'; StartupType = 'Disabled'
                   Why = 'Xbox accessory management.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'bthserv'; StartupType = 'Disabled'
                   Why = 'Bluetooth support. Virtual machines have no Bluetooth.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Features'
            Description = 'Remove old Windows components that only add attack surface.'
            Items       = @(
                @{ Type = 'Feature'; Roles = 'Both'; Name = 'SMB1Protocol'
                   Why = 'SMB version 1: 1980s-era, no encryption, the route used by EternalBlue and WannaCry. Nothing in the lab needs it.' }
                @{ Type = 'Feature'; Roles = 'Both'; Name = 'MicrosoftWindowsPowerShellV2Root'
                   Why = 'PowerShell 2.0. Attackers downgrade to it to dodge the logging and protections in newer versions.' }
                @{ Type = 'Feature'; Roles = 'Both'; Name = 'Internet-Explorer-Optional-amd64'
                   Why = 'Internet Explorer mode. Retired.' }
                @{ Type = 'Feature'; Roles = 'Client'; Name = 'WorkFolders-Client'
                   Why = 'Work Folders sync client. Not used.' }
                @{ Type = 'Feature'; Roles = 'Both'; Name = 'Printing-XPSServices-Features'
                   Why = 'XPS print path. Not used.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Performance'
            Description = 'Cut idle work and disk use. Sized for a lab VM on a shared SSD.'
            Items       = @(
                @{ Type = 'Hibernate'; Roles = 'Both'
                   Why = 'Hibernation off. Frees a hiberfil.sys the size of the VM RAM (4 GB or more per VM on a disk that has 200 GB for everything).' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Value = 0; Kind = 'DWord'
                   Why = 'Fast Startup off. It is a partial hibernation, so shutdown never fully stops the machine and updates and snapshots behave oddly.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisableLastAccessUpdate'; Value = 1; Kind = 'DWord'; BitMask = $true
                   Why = 'Stop writing a "last accessed" time on every file read. Fewer disk writes.' }
                @{ Type = 'Service'; Roles = 'Both'; Name = 'SysMain'; StartupType = 'Disabled'
                   Why = 'Superfetch pre-loads programs into memory. It helps a slow hard disk and wastes RAM and I/O on an SSD or a VM. Do not use this on a machine with a hard disk.' }
                @{ Type = 'Registry'; Roles = 'Server'; Path = 'HKLM:\SOFTWARE\Microsoft\ServerManager'; Name = 'DoNotOpenServerManagerAtLogon'; Value = 1; Kind = 'DWord'
                   Why = 'Server Manager does not start at every sign-in. Saves a slow, memory-hungry window.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Security'
            Description = 'Tighten old defaults that attackers rely on. Each is a common finding in a vulnerability scan.'
            Items       = @(
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; Name = 'RequireSecuritySignature'; Value = 1; Kind = 'DWord'
                   Why = 'SMB server requires signed messages, so a man-in-the-middle cannot alter or relay them.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name = 'RequireSecuritySignature'; Value = 1; Kind = 'DWord'
                   Why = 'SMB client requires signing too. Both ends must agree, or one refuses to talk.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Name = 'EnableMulticast'; Value = 0; Kind = 'DWord'
                   Why = 'LLMNR off. Name-resolution broadcast that Responder-style tools answer to steal password hashes.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'; Name = 'EnableMDNS'; Value = 0; Kind = 'DWord'
                   Why = 'mDNS off. Same class of local name-poisoning risk as LLMNR.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LmCompatibilityLevel'; Value = 5; Kind = 'DWord'
                   Why = 'NTLMv2 only; refuse the weak LM and NTLMv1 responses. Samba accepts NTLMv2, so the domain still works. It breaks very old devices.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RestrictAnonymous'; Value = 1; Kind = 'DWord'
                   Why = 'No anonymous listing of accounts and shares.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Value = 0; Kind = 'DWord'
                   Why = 'Do not keep clear-text passwords in memory for WDigest, where credential-theft tools read them.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoDriveTypeAutoRun'; Value = 255; Kind = 'DWord'
                   Why = 'AutoRun off for every drive type, so a USB stick cannot start a program by itself.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; Name = 'UserAuthentication'; Value = 1; Kind = 'DWord'
                   Why = 'Remote Desktop requires Network Level Authentication: you prove who you are before a session is created.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; Name = 'fAllowToGetHelp'; Value = 0; Kind = 'DWord'
                   Why = 'Remote Assistance off.' }
            )
        }

        # ---------------------------------------------------------------------------------
        @{
            Name        = 'Logging'
            Description = 'Record what a defender needs to see. These events feed Loki (docs/Logging.md).'
            Items       = @(
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name = 'EnableScriptBlockLogging'; Value = 1; Kind = 'DWord'
                   Why = 'Log the content of PowerShell scripts as they run (event 4104). Most attacks on Windows use PowerShell.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'; Name = 'ProcessCreationIncludeCmdLine_Enabled'; Value = 1; Kind = 'DWord'
                   Why = 'Process-start events include the command line, so you can see what was run, not only which program.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Security'; Name = 'MaxSize'; Value = 196608; Kind = 'DWord'
                   Why = 'Security log 192 MB (the default is 20 MB and wraps within hours on a busy host). Value is in KB.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\System'; Name = 'MaxSize'; Value = 65536; Kind = 'DWord'
                   Why = 'System log 64 MB.' }
                @{ Type = 'Registry'; Roles = 'Both'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Application'; Name = 'MaxSize'; Value = 65536; Kind = 'DWord'
                   Why = 'Application log 64 MB.' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Logon'; Setting = 'Success and Failure'
                   Why = 'Records every sign-in and failed sign-in (events 4624, 4625).' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Logoff'; Setting = 'Success'
                   Why = 'Records sign-outs, so you can tell how long a session lasted.' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Account Lockout'; Setting = 'Failure'
                   Why = 'Records lockouts: a sign of password guessing.' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Credential Validation'; Setting = 'Success and Failure'
                   Why = 'Records password checks.' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'User Account Management'; Setting = 'Success and Failure'
                   Why = 'Records accounts created, changed or deleted (4720, 4738).' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Security Group Management'; Setting = 'Success'
                   Why = 'Records changes to group membership, such as someone added to Administrators (4732).' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Process Creation'; Setting = 'Success'
                   Why = 'Records every program started (4688). Needs the command-line setting above to be useful.' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Special Logon'; Setting = 'Success'
                   Why = 'Records sign-ins with administrator rights (4672).' }
                @{ Type = 'AuditPol'; Roles = 'Both'; Name = 'Audit Policy Change'; Setting = 'Success'
                   Why = 'Records an attacker switching auditing off.' }
            )
        }
    )
}
