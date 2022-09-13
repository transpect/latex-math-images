module namespace eqimg = 'http://transpect.io/eqimg';

declare
  %rest:POST
  %rest:form-param("docx", "{$docx-map}")
  %rest:path("/eqimg/{$customization}/extract-formula")
  %rest:query-param("format", "{$format}", "eps")
  %rest:query-param("downscale", "{$downscale}", 2)
  %rest:query-param("basename", "{$basename}", 'formula')
function eqimg:extract-formula($docx-map as map(xs:string, item()+), $customization as xs:string, $format as xs:string, 
                               $downscale as xs:integer, $basename as xs:string?) {
  let $tmpdir as xs:string := file:create-temp-dir('docx-eqimg_', '')
  for $name in map:keys($docx-map)
    let $docx := ($docx-map($name))[1],
        $docx-basename := replace($name, '(.+/)?([^\.]+)\..*', '$2'),
        $zip-basename :=  $docx-basename || '_' ||  $basename || '.zip',
        $rest-path := '/eqimg/' || $customization || '/retrieve/' || file:name($tmpdir) || '/',
        $entries := archive:entries($docx)[matches(., 'word/(endnotes|footnotes|document)\d*?.xml$')],
        $job-id as xs:string := jobs:eval('file:delete("' || $tmpdir || '", true())', (), map { 'start':'PT180M', 'end':'PT181M' }),
        $omml-map as map(xs:string, item()?) := map:merge(
          for $e in $entries
          let $xml as document-node()? := parse-xml(archive:extract-text($docx, $e)),
              $prefix  := replace($e, '.*/(f|d|e)[^\d]+(\d+)?\.*', '$1$2'),
              $prelim_basename := $basename || '_' || (if (matches($prefix, '\d$')) then $prefix else concat($prefix,'0_'))
          return 
            if (exists($xml//(*:oMathPara | *:oMath[empty(parent::*:oMathPara)])))
            then  
              for $f in $xml//(*:oMathPara | *:oMath[empty(parent::*:oMathPara)])
              let $basename := concat($prelim_basename, format-number(count($f/preceding::*[self::*:oMathPara | self::*:oMath[empty(parent::*:oMathPara)]])+1,'0000'))
              return map{$basename : eqimg:render-omml($f ! document {.}, $customization, $format, false(), 
                                                                         false(), $downscale, $basename, false(), $tmpdir)
                        }
        ),
        $good-files as xs:string* := map:for-each($omml-map, function($key, $value){
                                      if ($value?status = 'error') then () else map:get($value, $format) => replace('^.*/retrieve/', '')
                                     }),
        $bad-files as xs:string* := map:for-each($omml-map, function($key, $value){
                                      if ($value?status = 'error') then map:get($value, 'texlog') => replace('^.*/retrieve/', '')
                                     }),
        $stripped-omml-map := map:merge(
                                map:for-each($omml-map, function($key, $value) {
                                                          map{ string-join(($key, '.', if ($value?status = 'error') then 'texlog' else $format)): 
                                                               map:remove($value, ('png', 'jpg', 'eps', 'svg', 'texlog')) }
                                                        })
                              ),
        $log-map := map:merge(
          (
            map{'status': if ('error' = $stripped-omml-map?*?status) then 'error' else 'success'},
            if ('error' = $stripped-omml-map?*?status) 
            then map{'message': 'One or more errors occured. The result contains the specific log files for each problematic formula. rendering'} else (), 
            map{'success': count($good-files)},
            map{'error': count($bad-files)},
            map{'rendering-output' : $stripped-omml-map}
          )
        ),
        $archive := archive:create(
          (
            for $file in $good-files
            let $fn := file:name($file), 
                $base := replace($fn,'\..*$', '')
            return ('img/' || $fn, 
                    'json/' || $base || '.json', 
                    'texlog/' || $base || '.log',
                    'tex/' || $base || '.tex',
                    'mml/' || $base || '.mml'
                    ),
            for $file in $bad-files
            let $fn := file:name($file), 
                $base := replace($fn,'\..*$', '')
            return ('json/' || $base || '.json', 
                    'texlog/' || $fn,
                    'tex/' || $base || '.tex',
                    'mml/' || $base || '.mml'
                    ), 
            $docx-basename || '_' ||  $basename || '.json'
          ),
          (
            for $file in $good-files
            let $base-with-path := replace($file,'\..*$', '')
            return (
              file:read-binary($tmpdir || $file), 
              json:serialize(
                map:get($stripped-omml-map, file:name($file)),
                map{'escape': false()}
              ),
              file:read-binary($tmpdir || $base-with-path || '.log'),
              file:read-binary($tmpdir || $base-with-path || '.tex'),
              file:read-binary($tmpdir || $base-with-path || '.mml')
            ),
            for $file in $bad-files
            let $base-with-path := replace($file,'\..*$', '')
            return (
              file:read-binary($tmpdir || $file), 
              json:serialize(
                map:get($stripped-omml-map, file:name($file)),
                map{'escape': false()}
              ),
              file:read-binary($tmpdir || $base-with-path || '.tex'),
              file:read-binary($tmpdir || $base-with-path || '.mml')
            ),
            json:serialize($log-map,map{'escape': false()})
          )
        ),
        $store := file:write-binary($tmpdir || '/' || $zip-basename, $archive)
    return json:serialize(
    map:merge(( 
                map{'input': $name },
                map{ 'status' : $log-map?status},
                if ($log-map?status = 'error') then map{ 'message' : $log-map?message},
                map{'result': $rest-path || $zip-basename }
             ),
              map{'duplicates': 'use-last'}
             ),
    map{'escape': false()}
  )
};

declare
  %rest:POST("{$omml}")
  %rest:path("/eqimg/{$customization}/render-omml")
  %rest:query-param("format", "{$format}", "eps")
  %rest:query-param("tex", "{$include-tex}", "false")
  %rest:query-param("mml", "{$include-mml}", "false")
  %rest:query-param("downscale", "{$downscale}", 2)
  %rest:query-param("basename", "{$basename}", 'formula')
  %rest:query-param("schedule-deletion", "{$schedule-deletion}", 'true')
  %rest:query-param("existing-tmpdir", "{$existing-tmpdir}")
  %rest:produces("text/json")
function eqimg:render-omml($omml as document-node(), $customization as xs:string, $format as xs:string, 
                           $include-tex as xs:boolean, $include-mml as xs:boolean, $downscale as xs:integer, $basename as xs:string?,
                           $schedule-deletion as xs:boolean, $existing-tmpdir as xs:string?) {
  let $result := xslt:transform-report($omml, 'omml2mml.xsl'),
      $mml := $result?result,
      $msgs := $result?messages
  return if ($mml instance of document-node())
  	 then parse-json(eqimg:render-mml($mml, $customization, $format, $include-tex, $include-mml, $downscale, $basename, $schedule-deletion, $existing-tmpdir))
	 else map{$basename: 'no-result'}
};

declare
  %rest:POST("{$mml}")
  %rest:path("/eqimg/{$customization}/render-mml")
  %rest:query-param("format", "{$format}", "eps")
  %rest:query-param("tex", "{$include-tex}", "false")
  %rest:query-param("include", "{$include-mml}", "false")
  %rest:query-param("downscale", "{$downscale}", 2)
  %rest:query-param("basename", "{$basename}", 'formula')
  %rest:query-param("schedule-deletion", "{$schedule-deletion}", 'true')
  %rest:query-param("existing-tmpdir", "{$existing-tmpdir}")
  %rest:produces("text/json")
function eqimg:render-mml($mml as document-node()?, $customization as xs:string, $format as xs:string, 
                          $include-tex as xs:boolean, $include-mml as xs:boolean, $downscale as xs:integer, $basename as xs:string?,
                          $schedule-deletion as xs:boolean, $existing-tmpdir as xs:string?) {
  let $tmpdir as xs:string := if ($existing-tmpdir) then file:create-temp-dir('eqimg', '', $existing-tmpdir) else file:create-temp-dir('eqimg', ''),
      $mml-path as xs:string := $tmpdir || '/' || $basename || '.mml',
      $nothing as item()* := file:write($mml-path, $mml),
      $tex as xs:string := xslt:transform-text(file:path-to-uri($mml-path), 'mml2tex.xsl'),
      $inputfile := $tmpdir || '/' || $basename || '.tex',
      $invocation-dir := file:current-dir() || '/' || 'latex-math-images',
      $outfile := $tmpdir || '/' ||  $basename  || '.' || $format,
      $logfile := $tmpdir || '/' ||  $basename  || '.log',
      $jsonfile := $tmpdir || '/' ||  $basename  || '.json',
      $rest-path := '/eqimg/' || $customization || '/retrieve/' || file:name($tmpdir) || '/'|| $basename,
      $nothing2 := file:write-text($inputfile, $tex),
      $job-id as xs:string := 
        if ($schedule-deletion) 
        then jobs:eval('file:delete("' || $tmpdir || '", true())', (), map { 'start':'PT180M', 'end':'PT181M' })
        else '',
      $args as xs:string+ := (
                                'build_formula.rb',
                                '-i', $inputfile, '-o', $outfile, '-l', $logfile, '-m', $jsonfile,
                                (if ($include-mml) then ('-E', '-M', $mml-path) else ()),
                                '-V', $customization, '-D', string($downscale)
                              ),
      $proc-result := proc:execute('ruby', $args, map{'dir': $invocation-dir, 'timeout': 60} ),
      $error := $proc-result/error,
      $props as map(xs:string, xs:string) :=
        if (file:exists($jsonfile))
        then (json:doc($jsonfile, map{'format': 'xquery'}) => map:remove('tex'))
        else map:entry('error', string-join((string-join($args, ' '), serialize($error), $jsonfile, $inputfile, $outfile, $customization), ' :: '))
  return json:serialize(
    map:merge((
                $props, 
                map{$format: $rest-path || '.' || $format},
                map{'texlog':$rest-path || '.' || 'log'},
                if ($include-mml) then map{'mml':   $rest-path || '.' || 'mml'},
                if ($include-tex) then map{'tex':   $rest-path || '.' || 'tex'},
                map{'status': if ($props?error) then 'error' 
                              else if ($props?image-height-pt = '0.0pt') then 'empty'
                                   else $props?status},
                if ($include-tex) then map{'tex': $tex => replace('"', '\\"')} else ()
             ),
              map{'duplicates': 'use-last'}
             ),
    map{'escape': false()}
  ) => replace('&#xa;', ' ') => replace('&#9;', ' ')
};

declare
  %rest:GET
  %rest:path("/eqimg/{$customization}/retrieve/{$tmpdir}/{$file}")
function eqimg:retrieve($file as xs:string, $tmpdir as xs:string, $customization as xs:string) {
  let $filepath as xs:string := '/tmp/' || $tmpdir || '/' || $file
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

