{{- define "web.name" -}}web{{- end }}

{{- define "web.labels" -}}
app: {{ include "web.name" . }}
app.kubernetes.io/name: {{ include "web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "web.selectorLabels" -}}
app: {{ include "web.name" . }}
{{- end }}