configuration SQLServerPrepareDsc
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$vmNamePrefix,

        [Parameter(Mandatory)]
        [String]$sqlInstanceName,

        [Parameter(Mandatory)]
        [Int]$vmCount,

	    [String]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName),

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SQLServicecreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AgtServicecreds,

        [Parameter(Mandatory=$true)]
        [String]$ClusterName,

        [Parameter(Mandatory=$true)]
        [String]$ClusterIP,

        [Parameter(Mandatory=$true)]
        [String]$witnessStorageBlobEndpoint,

        [Parameter(Mandatory=$true)]
        [String]$witnessStorageAccountKey,


        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30,

        [Parameter(Mandatory)]
        [String]$bloburi,
        [Parameter(Mandatory)]
        [String]$blobSAS,
        [parameter(Mandatory=$true)]
        [string]$Edition,
        [bool] $AttachDisk = $true,
        [bool] $WriteVault = $true,
        [string] $RoleID = "this_is_a_role_id",
        [string] $SecretID = "this_is_a_secret_id"
    )

    Import-DscResource -ModuleName xComputerManagement, xNetworking, xActiveDirectory, xStorage, xFailoverCluster, SqlServer, SqlServerDsc, StorageDSC, SmbShare, xSMBShare
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$DomainFQDNCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$SQLCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($SQLServicecreds.UserName)", $SQLServicecreds.Password)
    [System.Management.Automation.PSCredential]$AgtCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($AgtServicecreds.UserName)", $AgtServicecreds.Password)

    $SQLUserName=$SQLCreds.UserName
    $SQLPassword=$SQLCreds.GetNetworkCredential().password
    $AgtUserName=$AgtCreds.UserName
    $AgtPassword=$AgtCreds.GetNetworkCredential().password

    $ipcomponents = $ClusterIP.Split('.')
    $ipcomponents[3] = [convert]::ToString(([convert]::ToInt32($ipcomponents[3])) + 1)
    $ipdummy = $ipcomponents -join "."
    $ClusterNameDummy = "c" + $ClusterName

    $suri = [System.uri]$witnessStorageBlobEndpoint
    $uricomp = $suri.Host.split('.')

    $witnessStorageAccount = $uriComp[0]
    $witnessEndpoint = $uricomp[-3] + "." + $uricomp[-2] + "." + $uricomp[-1]

    $computerName = $env:COMPUTERNAME
    $domainUserName = $DomainCreds.UserName.ToString()

    [System.Collections.ArrayList]$Nodes=@()
    For ($count=0; $count -lt $vmCount; $count++) {
        $Nodes.Add($vmNamePrefix + $Count.ToString())
    }

    
    $ClusterOwnerNode = $Nodes[0]

    Node localhost
    {
		$Disk2PartitionStyle = Get-Disk | ?{ $_.Number -eq 2 } | %{ $_.PartitionStyle }
        if($AttachDisk -and ($Disk2PartitionStyle -eq 'RAW'))
        {
          xWaitforDisk Disk2
          {
            DiskId = 2
            RetryIntervalSec = 20
            RetryCount = 30
          }

          xDisk ADDataDisk {
            DiskId = 2
            DriveLetter = "F"
            DependsOn = "[xWaitForDisk]Disk2"
          }
        }
        if($WriteVault)
        {
          File C_Chef
          {
            Type = "Directory"
            Ensure = "Present"
            DestinationPath = "c:\chef"
          }

          File C_Chef_Hash
          {
            Type = "Directory"
            Ensure = "Present"
            DestinationPath = "c:\chef\hash"
          }
      
      $app_json_contents = "{ ```"role_id```":```"$RoleID```", ```"secret_id```":```"$SecretID```" }"
      $SetScript = @"
        `$app_json = "$app_json_contents"
        `$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding `$False
        [System.IO.File]::WriteAllLines("c:\chef\hash\app.json", `$app_json, `$Utf8NoBomEncoding)
"@
      $TestScript = @"
        `$app_json = "$app_json_contents"
        if(-not (Test-Path "c:\chef\hash\app.json"))
        {
          return `$false
        }
        return ((Get-content "c:\chef\hash\app.json") -join '') -eq "$app_json_contents"
"@
          Script BatFile
          {
            SetScript = [Scriptblock]::Create($SetScript)
            TestScript = [Scriptblock]::Create($TestScript)
            GetScript = { @{BatFileExists = (Test-Path "c:\chef\hash\app.json" )} }
          }
        }

        $date = (Get-Date)
        File timestamp
        {
          Ensure = "Present"
          DestinationPath = "c:\dsclog.txt"
          Contents = "Last DSC converge: $date"
        }

        WindowsFeature 'NetFramework35'
        {
            Name   = 'NET-Framework-Core'
            Ensure = 'Present'
        }

        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }

        WindowsFeature FC
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
        }

        WindowsFeature FailoverClusterTools 
        { 
            Ensure = "Present" 
            Name = "RSAT-Clustering-Mgmt"
            DependsOn = "[WindowsFeature]FC"
        } 

        WindowsFeature FCPS
        {
            Name = "RSAT-Clustering-PowerShell"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]FailoverClusterTools"
        }
     
        WindowsFeature FCPSCMD
        {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-CmdInterface'
            DependsOn = '[WindowsFeature]FCPS'
        }

        WindowsFeature ADPS
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }

        
        <#TODO: Add user for running SQL server.
        xADUser SvcUser
        {

        }
        #>

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
        }


	    Script New-ConfigurationFile {
            SetScript = {
                $bloburi=$using:bloburi
                $blobSAS=$using:blobSAS
                $Edition=$using:Edition

                Set-NetFirewallProfile -All -Enabled False -Verbose
                if((test-path -Path c:\SQLConfig) -eq $false) {
                    new-item -ItemType Directory -Path c:\ -Name SQLConfig
                }

                $nodes=$using:nodes
                $nodes | out-file C:\SQLConfig\nodes.txt
                # Download MSI file local
                if($Edition -eq 'Enterprise (x64)') {
                    $msiFileName = 'en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso'
                }
                else {
                    $msiFIleName = 'en_sql_server_2016_standard_with_service_pack_1_x64_dvd_9540929.iso'
                }
                $msiURI = "$bloburi/$msiFileName$blobSAS"

                $msiURI | out-file -FilePath C:\SQLConfig\log.txt
                Invoke-WebRequest -uri "$msiURI" -OutFile "c:\SQLConfig\$msiFileName"
                
            }
            TestScript = {
                $Edition=$using:Edition
                if($Edition -eq 'Enterprise (x64)') {
                    $msiFileName = 'en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso'
                }
                else {
                    $msiFIleName = 'en_sql_server_2016_standard_with_service_pack_1_x64_dvd_9540929.iso'
                }
                
                Test-Path "c:\SQLConfig\$msiFileName" 
            }
            GetScript = { }
            DependsOn = "[xComputer]DomainJoin"
        }

        if($Edition -eq 'Enterprise (x64)') {
           $msiFileName = 'en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso'
        }
        else {
           $msiFIleName = 'en_sql_server_2016_standard_with_service_pack_1_x64_dvd_9540929.iso'
        }
        MountImage ISO
        {
            ImagePath   = "c:\SQLConfig\$msiFileName"
            DriveLetter = 'S'
        }

        WaitForVolume WaitForISO
        {
            DriveLetter      = 'S'
            RetryIntervalSec = 5
            RetryCount       = 10
        }

        Script 'InstallNamedInstance-INST2016'{
            GetScript = { 
                return @{ 'Result' = $true }
            }

            SetScript = {

                $SQLUserName=$using:SQLUserName
                $SQLPassword=$using:SQLPassword

                $AgtUserName=$AgtCreds.UserName
                $AgtPassword=$AgtCreds.GetNetworkCredential().password

                s:\setup /ACTION='Install' /SQLBACKUPDIR='H:\Backups' /AGTSVCACCOUNT=$AgtUserName /SQLUSERDBDIR='H:\SQLDATA' /SQLSVCPASSWORD=$SQLPassword /AGTSVCSTARTUPTYPE='Automatic' /IACCEPTSQLSERVERLICENSETERMS='True' /SQLTEMPDBLOGDIR='L:\SQLLOG' /INSTALLSHAREDWOWDIR='F:\Program Files (x86)\Microsoft SQL Server' /AGTSVCPASSWORD=$AgtPassword /QUIET='True' /INSTANCENAME='CLUSTER1' /INSTANCEDIR='F:\Program Files\Microsoft SQL Server' /SQLUSERDBLOGDIR='L:\SQLLOG' /SQLSYSADMINACCOUNTS=$SQLUsername 'preprod\TWkXAMqnMP7VCVmEj9Fb' /SQLTEMPDBDIR='T:\SQLTMP' /SQLCOLLATION='SQL_Latin1_General_CP1_CI_AS' /SQLSVCACCOUNT=$SQLUsername /FEATURES=SQLENGINE,REPLICATION,FULLTEXT,CONN,BC,SDK /INSTALLSQLDATADIR='H:\' /INSTALLSHAREDDIR='C:\Program Files\Microsoft SQL Server' /UPDATEENABLED='False' /BROWSERSVCSTARTUPTYPE='Automatic'

            }

            TestScript = {
                $false
            }

            
            PsDscRunAsCredential = $DomainCreds
        }

        Script ResetSpns
        {
            GetScript = { 
                return @{ 'Result' = $true }
            }

            SetScript = {
                $spn = "MSSQLSvc/" + $using:computerName + "." + $using:DomainName
                
                $cmd = "setspn -D $spn $using:computerName"
                Write-Verbose $cmd
                Invoke-Expression $cmd

                $cmd = "setspn -A $spn $using:domainUsername"
                Write-Verbose $cmd
                Invoke-Expression $cmd

                $spn = "MSSQLSvc/" + $using:computerName + "." + $using:DomainName + ":1433"
                
                $cmd = "setspn -D $spn $using:computerName"
                Write-Verbose $cmd
                Invoke-Expression $cmd

                $cmd = "setspn -A $spn $using:domainUsername"
                Write-Verbose $cmd
                Invoke-Expression $cmd
            }

            TestScript = {
                $false
            }

            
            PsDscRunAsCredential = $DomainCreds
        }

        if ($ClusterOwnerNode -eq $env:COMPUTERNAME) { 
            SqlDatabase Create_Database
            {
                Ensure       = 'Present'
                ServerName   = $env:COMPUTERNAME
                InstanceName = $sqlInstanceName
                Name         = 'TestDB'

                PsDscRunAsCredential = $DomainCreds
            }
            
            xCluster CreateCluster
            {
                Name                          = $ClusterNameDummy
                StaticIPAddress               = $ipdummy
                DomainAdministratorCredential = $DomainCreds
                DependsOn                     = "[WindowsFeature]FCPSCMD","[Script]ResetSpns"
            }
            SqlAlwaysOnService EnableAlwaysOn
            {
                Ensure               = 'Present'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = $sqlInstanceName
                RestartTimeout       = 120
                DependsOn = "[xCluster]CreateCluster"
            }

            # Create a DatabaseMirroring endpoint
            SqlServerEndpoint HADREndpoint
            {
                EndPointName         = 'HADR'
                Ensure               = 'Present'
                Port                 = 5022
                ServerName           = $env:COMPUTERNAME
                InstanceName         = $sqlInstanceName
                DependsOn            = "[SqlAlwaysOnService]EnableAlwaysOn"
            }

            # Create the availability group on the instance tagged as the primary replica
            SqlAG CreateAG
            {
                Ensure               = "Present"
                Name                 = $ClusterName
                ServerName           = $env:COMPUTERNAME
                InstanceName         = $sqlInstanceName
                DependsOn            = "[SqlServerEndpoint]HADREndpoint"
                AvailabilityMode     = "SynchronousCommit"
                FailoverMode         = "Automatic" 
            }

            SqlAGListener AvailabilityGroupListener
            {
                Ensure               = 'Present'
                ServerName           = $ClusterOwnerNode
                InstanceName         = $sqlInstanceName
                AvailabilityGroup    = $ClusterName
                Name                 = $ClusterName
                IpAddress            = "$ClusterIP/255.255.255.0"
                Port                 = 1433
                PsDscRunAsCredential = $DomainCreds
                DependsOn            = "[SqlAG]CreateAG"
            }

            SqlWaitForAG WaitForAG
              {
                  Name                 = $ClusterName
                  RetryIntervalSec     = 20
                  RetryCount           = 30
                  PsDscRunAsCredential = $DomainCreds
                  DependsOn                  = "[SqlServerEndpoint]HADREndpoint"
              }

            File BackupDirectory
            {
                Ensure = "Present" 
                Type = "Directory" 
                DestinationPath = "F:\Backup"    
            }


            xSMBShare DBBackupShare
            {
                Name = "DBBackup"
                Path = "F:\Backup"
                Ensure = "Present"
                FullAccess = $DomainCreds.UserName
                Description = "Backup share for SQL Server"
                DependsOn = "[File]BackupDirectory"
            }

            SqlAGDatabase AddDatabaseToAG
            {
                AvailabilityGroupName   = $ClusterName
                BackupPath              = "\\" + $env:COMPUTERNAME + "\DBBackup"
                DatabaseName            = 'TestDB'
                InstanceName            = $sqlInstanceName
                ServerName              = $env:COMPUTERNAME
                Ensure                  = 'Present'
                ProcessOnlyOnActiveNode = $true
                PsDscRunAsCredential    = $DomainCreds
                DependsOn               = "[xSMBShare]DBBackupShare"
            }            

            Script SetProbePort
            {

                GetScript = { 
                    return @{ 'Result' = $true }
                }
                SetScript = {
                    $ipResourceName = $using:ClusterName + "_" + $using:ClusterIP
                    $ipResource = Get-ClusterResource $ipResourceName
                    $clusterResource = Get-ClusterResource -Name $using:ClusterName 

                    Set-ClusterParameter -InputObject $ipResource -Name ProbePort -Value 59999

                    Stop-ClusterResource $ipResource
                    Stop-ClusterResource $clusterResource

                    Start-ClusterResource $clusterResource #This should be enough
                    Start-ClusterResource $ipResource #To be on the safe side

                }
                TestScript = {
                    $ipResourceName = $using:ClusterName + "_" + $using:ClusterIP
                    $resource = Get-ClusterResource $ipResourceName
                    $probePort = $(Get-ClusterParameter -InputObject $resource -Name ProbePort).Value
                    Write-Verbose "ProbePort = $probePort"
                    ($(Get-ClusterParameter -InputObject $resource -Name ProbePort).Value -eq 59999)
                }
                DependsOn = "[SqlAGListener]AvailabilityGroupListener"
                PsDscRunAsCredential = $DomainCreds
            }

        } else {
            xWaitForCluster WaitForCluster
            {
                Name             = $ClusterNameDummy
                RetryIntervalSec = 10
                RetryCount       = 60
                DependsOn        = "[WindowsFeature]FCPSCMD"
            }

            #We have to do this manually due to a problem with xCluster:
            #  see: https://github.com/PowerShell/xFailOverCluster/issues/7
            #      - Cluster is added with an IP and the xCluster module tries to access this IP. 
            #      - Cluster is not not yet responding on that addreess
            Script JoinExistingCluster
            {
                GetScript = { 
                    return @{ 'Result' = $true }
                }
                SetScript = {
                    $targetNodeName = $env:COMPUTERNAME
                    Add-ClusterNode -Name $targetNodeName -Cluster $using:ClusterOwnerNode
                }
                TestScript = {
                    $targetNodeName = $env:COMPUTERNAME
                    $(Get-ClusterNode -Cluster $using:ClusterOwnerNode).Name -contains $targetNodeName
                }
                DependsOn = "[xWaitForCluster]WaitForCluster"
                PsDscRunAsCredential = $DomainCreds
            }

            SqlAlwaysOnService EnableAlwaysOn
            {
                Ensure               = 'Present'
                ServerName           = $env:COMPUTERNAME
                InstanceName         = $sqlInstanceName
                RestartTimeout       = 120
                DependsOn = "[Script]JoinExistingCluster"
            }

              # Create a DatabaseMirroring endpoint
              SqlServerEndpoint HADREndpoint
              {
                  EndPointName         = 'HADR'
                  Ensure               = 'Present'
                  Port                 = 5022
                  ServerName           = $env:COMPUTERNAME
                  InstanceName         = $sqlInstanceName
                  DependsOn            = "[SqlAlwaysOnService]EnableAlwaysOn"
              }
    

              SqlWaitForAG WaitForAG
              {
                  Name                 = $ClusterName
                  RetryIntervalSec     = 20
                  RetryCount           = 30
                  PsDscRunAsCredential = $DomainCreds
                  DependsOn                  = "[SqlServerEndpoint]HADREndpoint"
              }
      
                # Add the availability group replica to the availability group
                
                $computerName = $env:COMPUTERNAME
                SqlAGReplica AddReplica
                {
                    Ensure                     = 'Present'
                    Name                       = "$computerName\$sqlInstanceName"
                    AvailabilityGroupName      = $ClusterName
                    ServerName                 = $env:COMPUTERNAME
                    InstanceName               = $sqlInstanceName
                    PrimaryReplicaServerName   = $ClusterOwnerNode
                    PrimaryReplicaInstanceName = $sqlInstanceName
                    PsDscRunAsCredential = $DomainCreds
                    AvailabilityMode     = "SynchronousCommit"
                    FailoverMode         = "Automatic"
                    DependsOn            = "[SqlWaitForAG]WaitForAG"     
                }
        }


        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }
    }
}

function Get-NetBIOSName
{ 
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
}