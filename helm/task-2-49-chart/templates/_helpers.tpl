{{- define "task-2-49.name" -}}
{{ .Values.appName }}
{{- end -}}

{{- define "task-2-49.labels" -}}
app: {{ include "task-2-49.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}