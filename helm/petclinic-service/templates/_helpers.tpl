{{- define "petclinic.labels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.component }}
{{- end -}}

{{- define "petclinic.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/part-of: petclinic
{{- end -}}

{{- define "petclinic.image" -}}
{{- printf "%s.dkr.ecr.eu-central-1.amazonaws.com/petclinic-%s/%s:%s" .Values.image.account .Values.image.env .Values.image.name .Values.image.tag -}}
{{- end -}}

{{- define "petclinic.replicas" -}}
{{- if and .Values.replicaByService (hasKey .Values.replicaByService .Values.name) -}}
{{- index .Values.replicaByService .Values.name -}}
{{- else -}}
{{- .Values.replicaCount -}}
{{- end -}}
{{- end -}}

{{- define "petclinic.autoscaling" -}}
{{- if and .Values.autoscalingByService (hasKey .Values.autoscalingByService .Values.name) -}}
{{- index .Values.autoscalingByService .Values.name | toYaml -}}
{{- else -}}
{{- .Values.autoscaling | toYaml -}}
{{- end -}}
{{- end -}}

{{- define "petclinic.pdb" -}}
{{- if and .Values.podDisruptionBudgetByService (hasKey .Values.podDisruptionBudgetByService .Values.name) -}}
{{- index .Values.podDisruptionBudgetByService .Values.name | toYaml -}}
{{- else -}}
{{- .Values.podDisruptionBudget | toYaml -}}
{{- end -}}
{{- end -}}
