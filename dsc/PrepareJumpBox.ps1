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
        [String]$rgName
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
                    Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.201 -Force
                    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
                    Install-Package -Name docker -ProviderName DockerMsftProvider -Force
                    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\DSC -Name ModuledInstalled -Value "True"

                    Restart-Computer -Force 
                }

                if((test-path c:\aksdeploy) -eq $false) {
                    mkdir c:\aksdeploy
                }
                
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/ingress-demo.yaml -o C:\aksdeploy\ingress-demo.yaml
                
                $file = get-content C:\aksdeploy\ingress-demo.yaml
                $file -replace 'neilpeterson/aks-helloworld:v1',"$acrName.azurecr.io/aks-helloworld:latest" | out-file C:\aksdeploy\ingress-demo.yaml
                $file -replace 'loadBalancerIP: 10.240.0.25',"loadBalancerIP: $lbIP" | out-file C:\aksdeploy\ingress-demo.yaml
                "Logging into Azure" | out-file c:\aksdeploy\log.txt
                az login --identity >> c:\aksdeploy\log.txt

                "Getting AKS Creds" | out-file c:\aksdeploy\log.txt -Append
                az aks get-credentials --resource-group $rgName --name $aksName --file C:\aksdeploy\config >> c:\aksdeploy\log.txt
                "Creating namespace" | out-file c:\aksdeploy\log.txt -Append
                kubectl create namespace ingress-basic --kubeconfig C:\aksdeploy\config >> c:\aksdeploy\log.txt
                "ACr Login" | out-file c:\aksdeploy\log.txt -Append
                az acr login --name $acrName --expose-token >> c:\aksdeploy\log.txt
                "Attach AKS to ACR" | out-file c:\aksdeploy\log.txt -Append
                az aks update -n $aksName -g $rgName --attach-acr $acrName >> c:\aksdeploy\log.txt
                "Import image to ACR" | out-file c:\aksdeploy\log.txt -Append
                az acr import --name $acrName --source docker.io/neilpeterson/aks-helloworld:v1 --image aks-helloworld:latest >> c:\aksdeploy\log.txt

                "Apply Ingress Demo" | out-file c:\aksdeploy\log.txt -Append
                kubectl apply -f C:\aksdeploy\ingress-demo.yaml -n ingress-basic --kubeconfig C:\aksdeploy\config >> c:\aksdeploy\log.txt               
            }
            TestScript = {
                $aksName = $using:aksName
                $rgName = $using:rgName
                
                az login --identity
                az aks get-credentials --resource-group $rgName --name $aksName --file c:\aksdeploy\config
                $deployments = kubectl get deployments -n ingress-basic

                if($deployments -match 'ingress-demo') {
                    $true
                }
                else {
                    $false
                }
            }
            GetScript = { }
        }

    }
}
