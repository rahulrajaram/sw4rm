{{- define "sw4rm-reference-services.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}

{{- define "sw4rm-reference-services.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "sw4rm-reference-services.name" . -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "sw4rm-reference-services.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "sw4rm-reference-services.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "sw4rm-reference-services.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sw4rm-reference-services.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
