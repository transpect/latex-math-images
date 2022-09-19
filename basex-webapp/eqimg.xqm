module namespace eqimg = 'http://transpect.io/eqimg';

declare namespace html = 'http://www.w3.org/1999/xhtml';

declare
  %rest:POST
  %rest:form-param("docx", "{$docx-map}")
  %rest:path("/eqimg/{$customization}/extract-formula")
  %rest:query-param("format", "{$format}", "eps")
  %rest:query-param("downscale", "{$downscale}", 2)
function eqimg:extract-formula($docx-map as map(xs:string, item()+), $customization as xs:string, $format as xs:string, 
                               $downscale as xs:integer) {
  let $tmpdir as xs:string := file:create-temp-dir('docx-eqimg_', '')
  for $name in map:keys($docx-map)
    let $docx := ($docx-map($name))[1],
        $normalized-name := $name => replace('[^\w.]', '_'),
        $nothing := file:write-binary($tmpdir || $normalized-name, $docx)
    return eqimg:schedule-docx($customization, $tmpdir, $normalized-name, $format, $downscale)
           => parse-json()
           => map:remove('delete-job-id')
           => json:serialize(map{'escape': false()})
};

declare
function eqimg:schedule-docx($customization as xs:string, $tmpdir as xs:string, $name as xs:string, 
                             $format as xs:string, $downscale as xs:integer) {
    let $basename := 'formula',
        $docx-basename := replace($name, '(.+/)?([^\.]+)\..*', '$2'),
        $zip-basename :=  $docx-basename || '_' ||  $basename || '.zip',
        $docx := file:read-binary($tmpdir || $name),
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
                  map{'result': $rest-path || $zip-basename},
                  map{'delete-job-id': $job-id}
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
                                '-V', $customization, '-D', string($downscale), '-t', $tmpdir || 'work'
                              ),
      (: for debugging purposes :)
      $nothing3 := file:write-text($inputfile || '.args', string-join($args, ' ')),
      $proc-result := proc:execute('/usr/bin/ruby', $args, map{'dir': $invocation-dir, 'timeout': 60} ),
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


declare
  %rest:GET
  %rest:path("/eqimg/{$customization}/select")
  %output:method('html')
  %output:version('5.0')
function eqimg:select($customization) {
  let $maincontent := <main>
    <h1>Math Renderer</h1>
    <p>See <a href="https://subversion.le-tex.de/common/math-renderer/README.html">the documentation</a>
    for the options available, for command-line / HTTP client invocation, and for instructions on how
    to build and run this as a docker service on your computer.</p>
    <form method="post" enctype="multipart/form-data" action="/eqimg/{$customization}/upload-dispatcher">
      <p>
        <label for="fileselector">Select docx, OMML, or MathML file: </label>
        <input type="file" name="file" id="fileselector"/>
      </p>
      <p>
        <label for="format">Format: </label>
        <select id="format" name="format">
          <option value="eps">EPS</option>
          <option value="png">PNG</option>
          <option value="jpg">JPG</option>
        </select>
      </p>
      <p>
        <label for="downscale">Downscale factor (for raster formats): </label>
        <select id="downscale" name="downscale">
          <option value="1">1</option>
          <option value="2" selected="true">2</option>
          <option value="4">4</option>
          <option value="8">8</option>
        </select>
      </p>
      <p>
        <button>Submit</button>
      </p>
    </form>
    {eqimg:list-results($customization)}
  </main> 
  return eqimg:html((), 'Upload', $maincontent)
};

declare function eqimg:list-results($customization as xs:string) as item()* {
  if (db:exists('conversionjobs')) then
  let $results := db:open('conversionjobs')/json[delete-job-id = jobs:list()],
      $all-jobs := db:open('conversionjobs')/job[@id = $results/@id
                                                    or 
                                                    jobs:list-details(@id)/@state = ('cached', 'running', 'scheduled') ]
  return if (exists($all-jobs))
         then (
                <h2>Recent conversions  <button onClick="window.location.reload();"
                                            title="or hit Ctrl-R, F5, etc.">refresh</button></h2>,
                <table>
                  <tr>
                    <th>File</th>
                    <th>Timestamp (UTC)</th>
                    <th>Duration</th>
                    <th>Status</th>
                    <th>Format</th>
                    <th>Downscale</th>
                    <th>Download</th>
                    {(:<th>Details</th>:)}
                  </tr>
                  {for $j in $all-jobs
                   let $r := $results[@id = $j/@id]
                   order by $j/@start descending 
                   return <tr>
                      <td>{string($j/@filename)}</td>
                      <td>{string($j/@start)}</td>
                      <td>{($r/@duration, ($j/@id => jobs:list-details())/@duration)[1] ! (hours-from-duration(.), minutes-from-duration(.) => xs:integer() => format-integer('00'), 
                                                              seconds-from-duration(.) => xs:integer() => format-integer('00')) => string-join(':')}</td>
                      <td>{($r/status, string(jobs:list-details($j/@id)/@state))[1]}</td>
                      <td>{string($j/@format)}</td>
                      <td>{string($j/@downscale)}</td>
                      <td>{if (exists($r)) then <a href="{$r/result}">zip</a> else ()}</td>
                      {(:<td>{if (exists($r)) then <a 
                        href="/eqimg/{$customization}/zip-details?zip={$r/result ! replace(., '^.+/retrieve/', '')}">preview</a>
                        else ()}</td>:)}
                   </tr>
                  }
                </table>,
                <p>Conversion results will be kept for 3 hours.</p>
              )
         else (
           <p>Conversion results will be kept for 3 hours.</p>
         )
   else ()
};

declare 
%updating
function eqimg:glean-job-results($customization as xs:string) {
  let $jobs as element(job)* := db:open('conversionjobs')/job
  return 
    for $jid in $jobs/@id ! string(.)
    let $jd := jobs:list-details($jid)
    where $jd/@state = 'cached'
    return 
      for $result as xs:string? in jobs:result($jid)
      let $parsed-result as element(json) := json:parse($result)/json,
          $enhanced as element(json) := copy $pr := $parsed-result
                                        modify ( insert nodes $jd/(@* except @type) into $pr )
                                        return $pr
      return db:replace('conversionjobs', string-join(($enhanced/(@id, result)), '_'), $enhanced)
};

declare function eqimg:html ($body-class as xs:string?, $title as xs:string, $maincontent as item()*) {
  <html>
    <head>
      <meta charset="utf-8"/>
      <title>{$title}</title>
      <style>
      body {{ font-family: sans-serif; }}
      form {{ border-top: solid black 1pt; border-bottom: solid black 1pt; }}
      table {{ border-collapse: collapse; }}
      td, th {{ padding: 0.4em; }}
      td, th, table {{ border: solid black 1pt; }}
      </style>
    </head>
    <body>{if ($body-class) then attribute class {$body-class} else ()}
      {$maincontent}
    </body>
  </html>
};

declare
  %rest:POST
  %rest:path("/eqimg/{$customization}/upload-dispatcher")
  %rest:form-param("file", "{$file-map}")
  %rest:form-param("format", "{$format}", 'png')
  %rest:form-param("downscale", "{$downscale}", "2")
  %updating
function eqimg:upload-dispatcher($customization, $file-map, $format, $downscale as xs:string) {
  (: because of the redirect below, more than one uploaded file probably cannot
     be processed and should be flagged as an error :)
  for $filename in map:keys($file-map)
  let $normalized-filename := $filename => replace('[^\w.]', '_'),
      $type := switch($filename => replace('^.+\.(.+)$', '$1'))
               case 'docx'
               case 'docm'
                 return 'Word'
               case 'xml'
               case 'mml'
               case 'omml'
                 return switch (($file-map($filename)
                                  => bin:decode-string('utf-8') 
                                  => parse-xml())
                                 /*/local-name())
                        case 'math' return 'MathML'
                        case 'oMath'
                        case 'oMathPara' return 'OMML'
                        default return 'unknown XML'
               default return 'unknown',
      $tmpdir as xs:string := file:create-temp-dir(string-join(('docx-'[$type = 'Word'], 'eqimg_')), '')
  return update:output((
           file:write-binary($tmpdir || '/' || $normalized-filename, $file-map($filename)),
           web:redirect('/eqimg/' || $customization || '/schedule?type=' || $type || '&amp;tmpdir=' || $tmpdir
                        || '&amp;filename=' || $normalized-filename || '&amp;format=' || $format
                        || '&amp;downscale=' || $downscale)
         )),
  if (db:exists('conversionjobs')) then () else db:create('conversionjobs'),
  if (not(jobs:list() = 'glean-results'))
  then let $bogo := jobs:eval($eqimg:nsdecl ||
                             'eqimg:glean-job-results("' || $customization || '")',
                                                      (), map { 'start':'PT4S', 'interval': 'PT5S', 'id': 'glean-results'}
                             )
       return ()
  else ()
};

declare variable $eqimg:nsdecl := 'import module namespace eqimg="http://transpect.io/eqimg" at "eqimg.xqm"; ';

declare
  %rest:GET
  %rest:path("/eqimg/{$customization}/schedule")
  %rest:query-param("type", "{$type}")
  %rest:query-param("filename", "{$filename}")
  %rest:query-param("tmpdir", "{$tmpdir}")
  %rest:query-param("format", "{$format}", 'png')
  %rest:query-param("downscale", "{$downscale}", 2)
  %updating
function eqimg:schedule($customization, $type, $tmpdir, $filename, $format, $downscale as xs:integer) {
  update:output(web:redirect('/eqimg/' || $customization || '/select')),
  for $jobid in switch($type)
                  case 'Word' return jobs:eval($eqimg:nsdecl ||
                                               'eqimg:schedule-docx("' || $customization || '", "' || $tmpdir || 
                                                                    '", "' || $filename || '", "' || $format || 
                                                                    '", ' || $downscale|| ')',
                                                                    (), map { 'start':'PT0.1S', 'cache': true() }
                                              )
                  default return ()
  let $enhanced := copy $details := jobs:list-details($jobid)
                   modify (
                     insert nodes (
                       attribute downscale { $downscale },
                       attribute format { $format },
                       attribute filename { $filename },
                       attribute tmpdir { $tmpdir }
                     ) into $details
                   )
                   return $details
  return db:replace('conversionjobs', string-join(($jobid, $type, $filename), '_'), $enhanced)
};

