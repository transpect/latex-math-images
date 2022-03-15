<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" 
  xmlns:tr="http://transpect.io"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:mml="http://www.w3.org/1998/Math/MathML"
  exclude-result-prefixes="xs m tr"
  version="3.0">
  
  <xsl:import href="http://transpect.io/docx2hub/xsl/omml2mml/test-omml.xsl"/>
  
  <xsl:param name="debug"  select="'no'"/>
  
  <xsl:character-map  name="cleanups">
    <!-- override docx2hub/xsl/main.xsl’s U+2011 → U+2D mapping -->
    </xsl:character-map>

  <xsl:template match="/">
    <!-- convert ooml2mml with test-omml.xsl -->
    <xsl:variable name="mml_mml" as="element(*)"><!-- inlineequation or equation -->
      <xsl:next-match/>
    </xsl:variable>
    <xsl:variable name="mml2tex-grouping" as="map(xs:string, item())"
      select="transform(map{
                             'stylesheet-location': 'http://transpect.io/mml-normalize/xsl/mml-normalize.xsl',
                             'source-node': $mml_mml/*,
                             'initial-mode': xs:QName('mml2tex-grouping'),
                             'stylesheet-params': map{xs:QName('chars-from-which-to-convert-mi-to-mtext'): 2}
                           })"/>
    <xsl:variable name="mml2tex-preprocess" as="map(xs:string, item())"
      select="transform(map{
                             'stylesheet-location': 'http://transpect.io/mml-normalize/xsl/mml-normalize.xsl',
                             'source-node': $mml2tex-grouping?output,
                             'initial-mode': xs:QName('mml2tex-preprocess'),
                             'stylesheet-params': map{xs:QName('chars-from-which-to-convert-mi-to-mtext'): 2,
                                                      xs:QName('remove-mspace-next-to-operator-treshold-em'): 0.16}
                           })"/>

    <xsl:if test="$debug = 'yes'">
      <xsl:result-document href="debug01_omml2mml.xml" method="xml">
        <xsl:sequence select="$mml_mml"/>
      </xsl:result-document>
      <xsl:result-document href="debug11_mml2tex_grouping.xml" method="xml">
        <xsl:sequence select="$mml2tex-grouping?output"/>
      </xsl:result-document>
      <xsl:result-document href="debug13_mml2tex_preprocess.xml" method="xml">
        <xsl:sequence select="$mml2tex-preprocess?output"/>
      </xsl:result-document>
    </xsl:if>
    <xsl:sequence select="$mml2tex-preprocess?output"/>
  </xsl:template>
  
</xsl:stylesheet>