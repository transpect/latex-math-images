module namespace eqimg = 'http://transpect.io/eqimg';

declare
  %rest:POST("{$omml}")
  %rest:path("/eqimg/{$customization}/render-omml")
  %rest:query-param("format", "{$format}", "eps")
  %rest:query-param("tex", "{$include-tex}", "false")
  %rest:query-param("mml", "{$include-mml}", "false")
  %rest:produces("text/json")
function eqimg:render-omml($omml as document-node(), $customization as xs:string, $format as xs:string, 
                           $include-tex as xs:boolean, $include-mml as xs:boolean) {
  let $mml := xslt:transform($omml, 'omml2mml.xsl')
  return eqimg:render-mml($mml, $customization, $format, $include-tex, $include-mml)
};

declare
  %rest:POST("{$mml}")
  %rest:path("/eqimg/{$customization}/render-mml")
  %rest:query-param("format", "{$format}", "eps")
  %rest:query-param("tex", "{$include-tex}", "false")
  %rest:query-param("include", "{$include-mml}", "false")
  %rest:produces("text/json")
function eqimg:render-mml($mml as document-node(), $customization as xs:string, $format as xs:string, 
                          $include-tex as xs:boolean, $include-mml as xs:boolean) {
  let $tmpdir as xs:string := file:create-temp-dir('eqimg', ''),
      $mml-path as xs:string := $tmpdir || '/' || 'formula.mml',
      $nothing as item()* := file:write($mml-path, $mml),
      $tex as xs:string := xslt:transform-text(file:path-to-uri($mml-path), 'mml2tex.xsl'),
      $inputfile := $tmpdir || '/' || 'formula.tex',
      $invocation-dir := file:current-dir() || '/' || 'latex-math-images',
      $outfile := $tmpdir || '/out.' || $format,
      $logfile := $tmpdir || '/out.log',
      $jsonfile := $tmpdir || '/out.json',
      $job-id as xs:string := (
        file:write-text($inputfile, $tex),
        jobs:eval('file:delete("' || $tmpdir || '", true())', (), map { 'start':'PT60M', 'end':'PT61M' })
      ),
      $proc-result := proc:execute(
                                   'ruby', (
                                     'build_formula.rb',
                                     '-i', $inputfile, '-o', $outfile, '-l', $logfile, '-m', $jsonfile,
                                     (if ($include-mml) then ('-E', '-M', $mml-path) else ()),
                                     '-V', $customization
                                   ),
                                   map{'dir': $invocation-dir}
                                 ),
      $error := $proc-result/error,
      $props as map(xs:string, xs:string) :=
        if (file:exists($jsonfile))
        then (json:doc($jsonfile, map{'format': 'xquery'}) => map:remove('tex'))
        else map:entry('error', string-join(($error, $jsonfile, $inputfile, $outfile, $customization), ' :: '))
  return json:serialize(
    map:merge((
                $props, 
                map{$format: '/eqimg/' || $customization || '/retrieve/' || file:name($tmpdir) || '.' || $format},
                map{'texlog': '/eqimg/' || $customization || '/retrieve/' || file:name($tmpdir) || '.' || 'log'},
                map{'tex': '/eqimg/' || $customization || '/retrieve/' || file:name($tmpdir) || '.' || 'tex'},
                map{'status': if ($props?error) then 'error' 
                              else if ($props?image-height-pt = '0.0pt') then 'empty'
                                   else $props?status},
                if ($include-tex) then map{'tex': $tex => replace('"', '\\"')} else ()
             ),
              map{'duplicates': 'use-last'}
             ),
    map{'escape': false()}
  )
};

declare
  %rest:GET
  %rest:path("/eqimg/{$customization}/retrieve/{$filename}")
function eqimg:retrieve($filename as xs:string, $customization as xs:string) {
  let $tmpdir as xs:string := '/tmp/' || substring-before($filename, '.'),
      $ext as xs:string := substring-after($filename, '.'),
      $filepath as xs:string := $tmpdir || '/out.' || $ext
  return (
    web:response-header(
      map {'media-type': web:content-type( $filepath )},
      map {
        'Cache-Control': 'max-age=3600,public',
        'Content-Length': file:size( $filepath )
      }
    ),
    file:read-binary( $filepath )
  )
};

