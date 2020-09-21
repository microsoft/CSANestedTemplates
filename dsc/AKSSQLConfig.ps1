configuration configJumpBox
{
    param
    (
        [Parameter(Mandatory)]
        [String]$lbIP,

        [Parameter(Mandatory)]
        [String]$acrName,

        [Parameter(Mandatory)]
        [String]$aksName,

        [Parameter(Mandatory)]
        [String]$gwName,

        [Parameter(Mandatory)]
        [String]$rgName,

        [Parameter(Mandatory)]
        [String]$saName,

        [Parameter(Mandatory)]
        [String]$aiKey,

        [Parameter(Mandatory)]
        [String]$sqlName,

        [Parameter(Mandatory)]
        [String]$dbName,

        [Parameter(Mandatory)]
        [String]$sqlAdmin,

        [Parameter(Mandatory)]
        [String]$sqlPwd,

        [Parameter(Mandatory)]
        [String]$saKey
    )

    Node localhost
    {
	    Script InstallTools {
            SetScript = {
                $lbIP = $using:lbIP
                $acrName = $using:acrName
                $aksName = $using:aksName
                $gwName = $using:gwName
                $rgName = $using:rgName
                $saName = $using:saName
                $aiKey = $using:aiKey
                $sqlName = $using:sqlName
                $dbName = $using:dbName
                $sqlAdmin = $using:sqlAdmin
                $sqlPwd = $using:sqlPwd
                $saKey = $using:saKey

                if((test-path HKLM:\SOFTWARE\Microsoft\DSC) -eq $false) {
                    mkdir HKLM:\SOFTWARE\Microsoft\DSC
                }
                $moduleInstalled=$null
                $modulesInstalled = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\DSC -ErrorAction SilentlyContinue

                if($modulesInstalled.ModuledInstalled -ne 'True') {
                    curl https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/windows/amd64/kubectl.exe -o C:\windows\system32\kubectl.exe
                    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                    choco install kubernetes-helm --version 3.2.4 -y 
                    choco install openssl.light -y
                    Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.201 -Force
                    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
                    Install-Package -Name docker -ProviderName DockerMsftProvider -Force
                    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\DSC -Name ModuledInstalled -Value "True"
                    

                    Restart-Computer -Force 
                }

                if((test-path c:\aksdeploy) -eq $false) {
                    mkdir c:\aksdeploy
                }

                "Logging into Azure" | out-file c:\aksdeploy\log.txt
                az login --identity >> c:\aksdeploy\log.txt              

                    
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/secrets.yaml -o c:\aksdeploy\secrets.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/backend.yaml -o c:\aksdeploy\backend.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/frontend.yaml -o c:\aksdeploy\frontend.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/services.yaml -o c:\aksdeploy\services.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/SQL/dbbackup.bacpac -o c:\aksdeploy\dbbackup.bacpac
                
                # Place bacpac file in storage
                $file = "c:\aksdeploy\dbbackup.bacpac"
                $containerName = "sqlbackup"
                
                az storage container create --account-name $saName --account-key $saKey --name $containerName
                az storage blob upload --account-name $saName --account-key $saKey --container-name $containerName --name dbbackup.bacpac --file $file

                $edition = az sql db show -g $rgName -s $sqlName -n $dbName --query edition
                
                $dbConnectionString="Server=tcp:$sqlName.database.windows.net,1433;Initial Catalog=$dbName;Persist Security Info=False;User ID=azureuser;Password=$sqlPwd;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
                $dbConnectionString | out-file c:\aksdeploy\log.txt -Append

                $b64Connection = ($dbConnectionString | openssl base64) -replace " ",""
                $b64saName = ($saName | openssl base64) -replace " ",""
                $b64saKey = ($saKey | openssl base64) -replace " ",""
                $b64aiKey = ($aiKey | openssl base64) -replace " ",""

                $rawb64Connection = $dbConnectionString | openssl base64
                $b64Connection=$null
                foreach($line in $rawb64Connection) {
                    $b64Connection+=$line
                }
                $rawb64saName = $saName | openssl base64
                $b64saName = $null
                foreach($line in $rawb64saName) {
                    $b64saName+=$line
                }
                $rawb64saKey=$saKey | openssl base64
                $b64saKey = $null
                foreach($line in $rawb64saKey) {
                    $b64saKey+=$line
                }
                $rawb64aiKey=$aiKey | openssl base64
                $b64aiKey = $null
                foreach($line in $rawb64aiKey) {
                    $b64aiKey+=$line
                }
                
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<CONNECTIONSTRING>',"$b64Connection" | out-file c:\aksdeploy\secrets.yaml
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<SAKEY>',"$b64saKey" | out-file c:\aksdeploy\secrets.yaml
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<SANAME>',"$b64saName" | out-file c:\aksdeploy\secrets.yaml
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<AIKEY>',"$b64aiKey" | out-file c:\aksdeploy\secrets.yaml

                $file = get-content c:\aksdeploy\backend.yaml
                $file -replace '<ACRNAME>',"$acrName" | out-file c:\aksdeploy\backend.yaml

                $file = get-content c:\aksdeploy\frontend.yaml
                $file -replace '<ACRNAME>',"$acrName" | out-file c:\aksdeploy\frontend.yaml

                $file = get-content c:\aksdeploy\services.yaml
                $file -replace '<LBIP>',"$lbIP" | out-file c:\aksdeploy\services.yaml

                "Getting AKS Creds" | out-file c:\aksdeploy\log.txt -Append
                az aks get-credentials --resource-group $rgName --name $aksName --file c:\aksdeploy\config >> c:\aksdeploy\log.txt
                "Creating namespace" | out-file c:\aksdeploy\log.txt -Append
                kubectl create namespace ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                "ACr Login" | out-file c:\aksdeploy\log.txt -Append
                try {
                    az acr login --name $acrName --expose-token >> c:\aksdeploy\log.txt
                    "Attach AKS to ACR" | out-file c:\aksdeploy\log.txt -Append
                    az aks update -n $aksName -g $rgName --attach-acr $acrName >> c:\aksdeploy\log.txt
                }
                catch {
                    Out-Null
                }

		try {
                	"Attach AKS to ACR" | out-file c:\aksdeploy\log.txt -Append
                	az aks update -n $aksName -g $rgName --attach-acr $acrName >> c:\aksdeploy\log.txt
                	"Import image to ACR" | out-file c:\aksdeploy\log.txt -Append
                	az acr import --name $acrName --source docker.io/bwatts64/frontend:latest --image frontend:latest >> c:\aksdeploy\log.txt
                	az acr import --name $acrName --source docker.io/bwatts64/sessions-cleaner:latest --image sessions-cleaner:latest >> c:\aksdeploy\log.txt
                	az acr import --name $acrName --source docker.io/bwatts64/votings:latest --image votings:latest >> c:\aksdeploy\log.txt
                	az acr import --name $acrName --source docker.io/bwatts64/sessions:latest --image sessions:latest >> c:\aksdeploy\log.txt
		}
		catch {
			Out-Null
		}

                $saURI="$(az storage account show -n $saName -g $rgName --query primaryEndpoints.blob)sqlbackup/dbbackup.bacpac" -replace """",""
                az sql db import -s $sqlName -n $dbName -g $rgName -p $sqlPwd -u $sqlAdmin --storage-key $saKey --storage-key-type StorageAccessKey --storage-uri $saURI

                kubectl apply -f c:\aksdeploy\secrets.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                kubectl apply -f c:\aksdeploy\frontend.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                kubectl apply -f c:\aksdeploy\backend.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                kubectl apply -f c:\aksdeploy\services.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
            }
            TestScript = { 
                $aksName = $using:aksName
                $rgName = $using:rgName
                try {
                    az login --identity | Out-Null
                    az aks get-credentials --resource-group $rgName --name $aksName --file c:\aksdeploy\config | Out-Null

                    $deployments = kubectl get deployments --all-namespaces --kubeconfig c:\aksdeploy\config
                
                    if($deployments -match 'sessionbrowser-deployment' -and $deployments -match 'sessions-ms-deployment' -and $deployments -match 'votings-ms-deployment') {
                        return $true
                    }
                    else {
                        return $false
                    }
                }
                catch {
                    return $false
                }
            }
            GetScript = { }
        }

    }
}
