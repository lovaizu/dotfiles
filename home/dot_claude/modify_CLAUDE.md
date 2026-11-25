{{- /* chezmoi:modify-template */ -}}
{{- /*
  sbx writes its own sections into this file inside a sandbox, so the
  template replaces only the part between the two markers and leaves the
  rest as found. Claude Code strips the markers, as HTML comments, before
  the instructions reach Claude.
  A file from before the markers holds the instructions as they were
  placed, and gets the markers around them where they stand. Any other
  file gets the marked part at its end.
*/ -}}
{{- $start := "<!-- lovaizu/dotfiles start -->" -}}
{{- $end := "<!-- lovaizu/dotfiles end -->" -}}
{{- $body := include ".chezmoitemplates/CLAUDE.md" -}}
{{- $block := printf "%s\n%s%s\n" $start $body $end -}}
{{- $live := .chezmoi.stdin -}}
{{- if and (contains $start $live) (contains $end $live) -}}
{{- $head := splitn $start 2 $live -}}
{{- $tail := splitn $end 2 $head._1 -}}
{{- $head._0 }}{{ $block }}{{ $tail._1 | trimPrefix "\n" -}}
{{- else if and $live (contains $body $live) -}}
{{- $live | replace $body $block -}}
{{- else if $live -}}
{{- $live | trimSuffix "\n" }}

{{ $block -}}
{{- else -}}
{{- $block -}}
{{- end -}}
