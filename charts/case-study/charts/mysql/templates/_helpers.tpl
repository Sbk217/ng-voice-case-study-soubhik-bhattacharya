{{- define "mysql.name" -}}mysql{{- end }}

{{- define "mysql.labels" -}}
app: {{ include "mysql.name" . }}
app.kubernetes.io/name: {{ include "mysql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "mysql.selectorLabels" -}}
app: {{ include "mysql.name" . }}
{{- end }}