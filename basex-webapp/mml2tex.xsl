<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fn="http://www.w3.org/2005/xpath-functions"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" 
  xmlns:saxon="http://saxon.sf.net/" 
  xmlns:tr="http://transpect.io"
  xmlns:mml="http://www.w3.org/1998/Math/MathML"
  exclude-result-prefixes="xs"
  version="3.0">
  
  <xsl:import href="http://transpect.io/mml2tex/xsl/mml2tex.xsl"/>
  
  <xsl:param name="debug"  select="'no'"/>
  <xsl:param name="fail-on-error" select="'no'"/>
  
  <xsl:template match="/">
    <xsl:variable name="omml2tex" as="map(xs:string, item())" 
      select="transform(map{
                             'stylesheet-location': 'http://transpect.io/mml2tex/xsl/mml2tex.xsl',
                             'source-node': /,
                             'initial-mode': xs:QName('mathml2tex'),
                             'stylesheet-params':map {xs:QName('debug'): $debug,
                                                      xs:QName('katex'): 'yes',
                                                      xs:QName('fail-on-error'): $fail-on-error}
                           })">
      <!-- katex=yes: Only use \left and \right when processing mfenced, not for parentheses in mo elts -->
    </xsl:variable>
    <!--<xsl:variable name="math-delim" as="xs:string" select="if($mml_mml/*:equation) then '$$' else '$'"/>-->
    <xsl:variable name="math-delim" as="xs:string" select="'$'"/>
    <xsl:result-document method="text" item-separator="">
      <xsl:sequence select="$math-delim"/>
      <xsl:sequence select="if(/mml:math/@display = 'block') then '\displaystyle ' else ''"/>
      <xsl:sequence select="$omml2tex?output"/>
      <xsl:sequence select="$math-delim"/>
    </xsl:result-document>
  </xsl:template>
  
</xsl:stylesheet>
