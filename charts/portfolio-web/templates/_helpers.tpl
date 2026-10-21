{{- define "portfolio-web.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "portfolio-web.labels" -}}
app.kubernetes.io/name: {{ include "portfolio-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "portfolio-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "portfolio-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "portfolio-web.image" -}}
{{- $registry := required "image.registry is required (from the portfolio/ecr-registry annotation)" .Values.image.registry -}}
{{- $tag := required "image.tag is required (from values-prod.yaml)" .Values.image.tag -}}
{{- printf "%s/%s:%s" $registry .Values.image.repository $tag -}}
{{- end -}}
