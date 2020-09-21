while getopts l:a:k:g:r: option
do
case "${option}"
in
l) lbIP=${OPTARG};;
a) acrName=${OPTARG};;
k) aksName=${OPTARG};;
g) gwName=${OPTARG};;
r) rgName=${OPTARG};;
esac
done

mkdir aksdeploy
                
curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/ingress-demo.yaml -o ./aksdeploy/ingress-demo.yaml
                
sed -i "s/neilpeterson\/aks-helloworld:v1/$acrName\/aks-helloworld:latest/" ./aksdeploy/ingress-demo.yaml
$file = get-content ./aksdeploy/ingress-demo.yaml
$file -replace 'loadBalancerIP: 10.240.0.25',"loadBalancerIP: $lbIP" | out-file ./aksdeploy/ingress-demo.yaml
sed -i "s/loadBalancerIP: 10.240.0.25/loadBalancerIP: $lbIP/" ./aksdeploy/ingress-demo.yaml

az aks get-credentials --resource-group "$rgName" --name "$aksName" --file ./aksdeploy/config 
kubectl create namespace ingress-basic --kubeconfig ./aksdeploy/config 

az acr login --name "$acrName" --expose-token 
az aks update -n "$aksName" -g "$rgName" --attach-acr "$acrName" 
az acr import --name "$acrName" --source docker.io/neilpeterson/aks-helloworld:v1 --image aks-helloworld:latest

kubectl apply -f ./aksdeploy/ingress-demo.yaml -n ingress-basic --kubeconfig ./aksdeploy/config               
        