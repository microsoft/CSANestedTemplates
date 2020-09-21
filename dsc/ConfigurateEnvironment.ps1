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
if((test-path c:\aksdeploy) -eq $false) {
    mkdir aksdeploy
}
                
curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/ingress-demo.yaml -o ./aksdeploy/ingress-demo.yaml
                
$file = get-content ./aksdeploy/ingress-demo.yaml
$file -replace 'neilpeterson/aks-helloworld:v1',"$acrName.azurecr.io/aks-helloworld:latest" | out-file ./aksdeploy/ingress-demo.yaml
$file = get-content ./aksdeploy/ingress-demo.yaml
$file -replace 'loadBalancerIP: 10.240.0.25',"loadBalancerIP: $lbIP" | out-file ./aksdeploy/ingress-demo.yaml

"Getting AKS Creds" | out-file ./aksdeploy/log.txt -Append
az aks get-credentials --resource-group testarm --name poc-AKSResource --file ./aksdeploy/config >> ./aksdeploy/log.txt
"Creating namespace" | out-file ./aksdeploy/log.txt -Append
kubectl create namespace ingress-basic --kubeconfig ./aksdeploy/config >> ./aksdeploy/log.txt
"Getting appgw" | out-file ./aksdeploy/log.txt -Append
az extension add --name aks-preview
$appgwId=$(az network application-gateway show -n $gwName -g $rgName -o tsv --query "id")
"Enabling AppGW addon" | out-file ./aksdeploy/log.txt -Append 
az aks enable-addons -n $aksName -g $rgName -a ingress-appgw --appgw-id $appgwId
"ACr Login" | out-file ./aksdeploy/log.txt -Append
az acr login --name $acrName --expose-token >> ./aksdeploy/log.txt
"Attach AKS to ACR" | out-file ./aksdeploy/log.txt -Append
az aks update -n $aksName -g $rgName --attach-acr $acrName >> ./aksdeploy/log.txt
"Import image to ACR" | out-file ./aksdeploy/log.txt -Append
az acr import --name $acrName --source docker.io/neilpeterson/aks-helloworld:v1 --image aks-helloworld:latest >> ./aksdeploy/log.txt

"Apply Ingress Demo" | out-file ./aksdeploy/log.txt -Append
kubectl apply -f ./aksdeploy/ingress-demo.yaml -n ingress-basic --kubeconfig ./aksdeploy/config >> ./aksdeploy/log.txt               
        