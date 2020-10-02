{{/*
Print expanded value literally.

Call this function like this:
{{ template "printLiteral" (dict "string" .Values.database.password) }}
*/}}
{{- define "printLiteral" -}}
{{- $string := .string -}}
{{- printf "%s" $string -}}
{{- end }}

{{/*
Print expanded value literally including surrounding single quotes.

Call this function like this:
{{ template "printLiteralString" (dict "string" .Values.database.password) }}
*/}}
{{- define "printLiteralString" -}}
{{- $string := .string -}}
{{- printf "'%s'" $string -}}
{{- end }}

{{/*
Insert infix into ".Values.ingress.hostname".

If ".Values.ingress.hostname" contains "mobile.domain.tld",
and ".Values.debug.customHostnameInfix" contains "staging",
then this function will convert "mobile.domain.tld" to "mobile.staging.domain.tld".

Call this function like this:
{{ template "insertIngressHostnameInfix" (dict "infix" .Values.debug.customHostnameInfix "initialHostname" .Values.ingress.hostname) }}
*/}}
{{- define "insertIngressHostnameInfix" -}}
{{- $infix := .infix -}}
{{- $initialHostname := .initialHostname -}}
{{- $pureHostname := .initialHostname | trimSuffix ".domain.tld" -}}
{{- $hostname :=  printf "%s%s%s%s" $pureHostname "." $infix ".domain.tld" -}}
{{- printf "%s" $hostname -}}
{{- end }}
