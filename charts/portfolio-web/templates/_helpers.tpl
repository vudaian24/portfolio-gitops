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
{{- /* values-prod.yaml is written by portfolio-web CI; accept only a full git SHA and our own repository. */ -}}
{{- if not (regexMatch "^[0-9a-f]{40}$" (toString $tag)) -}}
{{- fail (printf "image.tag must be a 40-character git SHA, got %q" (toString $tag)) -}}
{{- end -}}
{{- if ne .Values.image.repository "portfolio-prod-web" -}}
{{- fail (printf "image.repository must be portfolio-prod-web, got %q" (toString .Values.image.repository)) -}}
{{- end -}}
{{- printf "%s/%s:%s" $registry .Values.image.repository $tag -}}
{{- end -}}
