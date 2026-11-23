package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

// in-cluster config when running as a pod, ~/.kube/config when run locally
func loadConfig() (*rest.Config, error) {
	if cfg, err := rest.InClusterConfig(); err == nil {
		return cfg, nil
	}
	return clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
}

func ready(p *corev1.Pod) bool {
	for _, c := range p.Status.Conditions {
		if c.Type == corev1.PodReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	ns := os.Getenv("WATCH_NAMESPACE") // empty = all namespaces

	cfg, err := loadConfig()
	if err != nil {
		log.Error("load kube config", "err", err)
		os.Exit(1)
	}
	client, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		log.Error("create client", "err", err)
		os.Exit(1)
	}

	// Informer = list once + watch, with automatic reconnects and a local cache
	factory := informers.NewSharedInformerFactoryWithOptions(client, 10*time.Minute, informers.WithNamespace(ns))
	podInformer := factory.Core().V1().Pods().Informer()

	_, err = podInformer.AddEventHandler(cache.ResourceEventHandlerDetailedFuncs{
		AddFunc: func(obj interface{}, isInInitialList bool) {
			p := obj.(*corev1.Pod)
			if isInInitialList { // pods that already existed at startup
				log.Info("pod existing", "namespace", p.Namespace, "pod", p.Name, "phase", p.Status.Phase)
				return
			}
			log.Info("pod created", "namespace", p.Namespace, "pod", p.Name, "phase", p.Status.Phase)
		},
		UpdateFunc: func(oldObj, newObj interface{}) {
			o, n := oldObj.(*corev1.Pod), newObj.(*corev1.Pod)
			if o.ResourceVersion == n.ResourceVersion { // periodic resync, no real change
				return
			}
			log.Info("pod updated", "namespace", n.Namespace, "pod", n.Name,
				"oldPhase", o.Status.Phase, "newPhase", n.Status.Phase,
				"ready", ready(n), "node", n.Spec.NodeName, "podIP", n.Status.PodIP)
		},
		DeleteFunc: func(obj interface{}) {
			p, ok := obj.(*corev1.Pod)
			if !ok { // missed the final state while disconnected
				tomb, ok := obj.(cache.DeletedFinalStateUnknown)
				if !ok {
					return
				}
				if p, ok = tomb.Obj.(*corev1.Pod); !ok {
					return
				}
			}
			log.Info("pod deleted", "namespace", p.Namespace, "pod", p.Name)
		},
	})
	if err != nil {
		log.Error("add event handler", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	factory.Start(ctx.Done())
	if !cache.WaitForCacheSync(ctx.Done(), podInformer.HasSynced) {
		log.Error("cache sync failed")
		os.Exit(1)
	}
	log.Info("pod monitor started", "namespace", ns)
	<-ctx.Done()
	log.Info("shutting down")
}
