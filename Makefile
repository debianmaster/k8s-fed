
define renameConfig
    sed -e 's/default/$1/g' -e 's/localhost/k3d-$1-server/g' ~/.k3d/$1/kubeconfig.yaml >  ~/.kube/$1.yaml
endef


define setupStorage
	kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml --context=$1
	kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' --context=$1
endef


define patchCluster

	kubectl patch --context=oc -n kube-federation-system kubefedclusters "${1}" \
		--type='merge' \
		--patch '{"spec": {"caBundle": "$(shell kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'"${1}"'")].cluster.certificate-authority-data}')"}}' 
endef

cc: 
	k3d create -n oc  -p 1043  --publish 1080:80 --publish 1443:443 -x --tls-san="lab.rsc7.id,13.229.84.229"
	k3d create -n uc1 -p 2043  --publish 2080:80 --publish 2443:443 -x --tls-san="lab.rsc7.id,13.229.84.229"
	k3d create -n uc2 -p 3043  --publish 3080:80 --publish 3443:443 -x --tls-san="lab.rsc7.id,13.229.84.229"

clean:
	k3d delete --all
	rm -rf ~/.kube
	rm -rf ~/.k3d
	rm -rf ~/.config

config:
	rm -rf ~/.k3d
	cp -R ~/.config/k3d ~/.k3d/
	mkdir -p ~/.kube && cp merge ~/.kube
	ls -lrt ~/.config/k3d/oc
	$(call renameConfig,oc)
	$(call renameConfig,uc1)
	$(call renameConfig,uc2)

	export KUBECONFIG=~/.kube/merge:~/.kube/oc.yaml:~/.kube/uc1.yaml:~/.kube/uc2.yaml
	echo '192.168.5.92 k3d-oc-server k3d-uc1-server k3d-uc2-server'

storage:
	$(call setupStorage,oc)
	$(call setupStorage,uc1)
	$(call setupStorage,uc2)
nw:
	docker network connect k3d-oc k3d-uc1-server
	docker network connect k3d-oc k3d-uc2-server

nwd: 
	docker network disconnect k3d-oc k3d-uc1-server
	docker network disconnect k3d-oc k3d-uc2-server

fed:
	helm repo add kubefed-charts https://raw.githubusercontent.com/kubernetes-sigs/kubefed/master/charts
	kubectl apply -f sa-setup.yaml --context=oc
	helm init --service-account tiller --kube-context=oc --wait
	helm install kubefed-charts/kubefed --name kubefed --version=0.1.0-rc3 --namespace kube-federation-system --kube-context=oc

join:
	kubefedctl join uc1 --cluster-context uc1 --host-cluster-context oc --v=2
	kubefedctl join uc2 --cluster-context uc2 --host-cluster-context oc --v=2
	kubefedctl join oc --cluster-context oc --host-cluster-context oc --v=2

unjoin:
	kubefedctl unjoin oc --cluster-context oc --host-cluster-context oc --v=2
	kubefedctl unjoin uc1 --cluster-context uc1 --host-cluster-context oc --v=2
	kubefedctl unjoin uc2 --cluster-context uc2 --host-cluster-context oc --v=2

patch:
	$(call patchCluster,uc1)
	$(call patchCluster,uc2)
	$(call patchCluster,oc)

status:
	kubectl -n kube-federation-system get kubefedclusters --context=oc

gen:
	k3d get-kubeconfig --name='oc' && sleep 1
	k3d get-kubeconfig --name='uc1' && sleep 1
	k3d get-kubeconfig --name='uc2' && sleep 1


all:
	make clean
	make cc
	sleep 10
	make config
	make storage
	make nw
	make fed
	make join

rancher:
	curl --insecure -sfL https://lab.rsc7.id/v3/import/gjmkfssnxscwxd6twpzk9jvqj58hmzw95xbbpfkg7gwmv9sz7frqzm.yaml | kubectl apply --context=oc -f -
	curl --insecure -sfL https://lab.rsc7.id/v3/import/qsd6skjx7qwmz2qcmg2849xn2hjlx5lxkmbrll97c9q7rp5wgffffw.yaml | kubectl apply --context=uc1 -f -
	curl --insecure -sfL https://lab.rsc7.id/v3/import/x6dm7jsp27bw55wkm6bfdfw2z6g7dzvf49b9hms96lc5dwr8qs2v9r.yaml | kubectl apply --context=uc2 -f -

