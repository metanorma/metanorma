module Metanorma
  class Collection
    class Multilingual
      def to_xml(node)
        node&.to_xml(encoding: "UTF-8", indent: 0,
                     save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
      end

      def xmldoc(node)
        ret = Nokogiri::XML::Document.new
        ret.root = node.dup
        ret
      end

      def flatxml_step1(param, elements)
        <<~XSLT
          <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
          xmlns:fo="http://www.w3.org/1999/XSL/Format"
          xmlns:jcgm="https://www.metanorma.org/ns/bipm"
          xmlns:bipm="https://www.metanorma.org/ns/bipm"
          xmlns:mathml="http://www.w3.org/1998/Math/MathML"
          xmlns:xalan="http://xml.apache.org/xalan"
          xmlns:exsl="http://exslt.org/common"
          xmlns:fox="http://xmlgraphics.apache.org/fop/extensions"
          xmlns:java="http://xml.apache.org/xalan/java"
          exclude-result-prefixes="java"
          version="1.0">

          <xsl:output method="xml" encoding="UTF-8" indent="no"/>

          <xsl:template match="@* | node()">
            <xsl:copy>
              <xsl:apply-templates select="@* | node()"/>
            </xsl:copy>
          </xsl:template>

          <xsl:template match="/*[local-name()='doc-container']">
          <xsl:copy>
          <xsl:apply-templates  select="@* | node()" mode="flatxml_step1">
                  <xsl:with-param name="num" select="'#{param}'"/>
          </xsl:apply-templates>
          </xsl:copy>
          </xsl:template>

          <xsl:param name="align-cross-elements">#{elements}</xsl:param>

          <xsl:variable name="align_cross_elements_default">clause</xsl:variable>
          <xsl:variable name="align_cross_elements_doc">
            <xsl:choose>
              <xsl:when test="normalize-space($align-cross-elements) != ''"><xsl:value-of select="$align-cross-elements"/></xsl:when>
              <xsl:otherwise>
                <xsl:value-of select="normalize-space((//jcgm:bipm-standard)[1]/jcgm:bibdata/jcgm:ext/jcgm:parallel-align-element)"/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <xsl:variable name="align_cross_elements_">
            <xsl:choose>
              <xsl:when test="$align_cross_elements_doc != ''">
                <xsl:value-of select="$align_cross_elements_doc"/>
              </xsl:when>
              <xsl:otherwise>
                <xsl:value-of select="$align_cross_elements_default"/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <xsl:variable name="align_cross_elements">
            <xsl:text>#</xsl:text><xsl:value-of select="translate(normalize-space($align_cross_elements_), ' ', '#')"/><xsl:text>#</xsl:text>
          </xsl:variable>

          <!-- ================================= -->
          <!-- First step -->
          <!-- ================================= -->

          <xsl:template match="@*|node()" mode="flatxml_step1">
            <xsl:copy>
              <xsl:apply-templates select="@*|node()" mode="flatxml_step1"/>
            </xsl:copy>
          </xsl:template>
          <xsl:template match="/*[local-name()='doc-container']/*[1]" mode="flatxml_step1">
            <xsl:param name="num"/>
            <xsl:copy>
               <xsl:attribute name="cross-align">true</xsl:attribute>
              <xsl:attribute name="{$num}"/>
              <xsl:apply-templates select="@*"/>
              <xsl:apply-templates select="node()" mode="flatxml_step1"/>
            </xsl:copy>
          </xsl:template>

          <!-- enclose clause[@type='scope'] into scope -->
          <xsl:template match="*[local-name()='sections']/*[local-name()='clause'][@type='scope']" mode="flatxml_step1" priority="2">
          <!-- <section_scope>
            <clause @type=scope>...
          </section_scope> -->
          <xsl:element name="section_scope" namespace="https://www.metanorma.org/ns/bipm">
            <xsl:call-template name="clause"/>
          </xsl:element>
                  </xsl:template>

                  <xsl:template match="jcgm:sections//jcgm:clause | jcgm:annex//jcgm:clause" mode="flatxml_step1" name="clause">
                  <!-- From:
                    <clause>
                    <title>...</title>
                    <p>...</p>
                    </clause>
                    To:
                    <clause/>
                    <title>...</title>
                    <p>...</p>
                  -->
                    <xsl:copy>
                      <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                      <xsl:call-template name="setCrossAlignAttributes"/>
                    </xsl:copy>
                    <xsl:apply-templates mode="flatxml_step1"/>
                  </xsl:template>

                  <!-- allow cross-align for element title -->
                  <xsl:template match="jcgm:sections//jcgm:title | jcgm:annex//jcgm:title" mode="flatxml_step1">
                    <xsl:copy>
                      <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                      <xsl:call-template name="setCrossAlignAttributes"/>
                      <xsl:attribute name="keep-with-next">always</xsl:attribute>
                      <xsl:if test="parent::jcgm:annex">
                        <xsl:attribute name="depth">1</xsl:attribute>
                      </xsl:if>
                      <xsl:if test="../@inline-header = 'true'">
                        <xsl:copy-of select="../@inline-header"/>
                      </xsl:if>
                      <xsl:apply-templates mode="flatxml_step1"/>
                    </xsl:copy>
                  </xsl:template>

                  <xsl:template match="*[local-name()='annex']" mode="flatxml_step1">
                    <xsl:copy>
                      <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                      <!-- create empty element for case if first element isn't cross-align -->
                      <xsl:element name="empty" namespace="https://www.metanorma.org/ns/bipm">
                        <xsl:attribute name="cross-align">true</xsl:attribute>
                        <xsl:attribute name="element-number">empty_annex<xsl:number/></xsl:attribute>
                      </xsl:element>
                      <xsl:apply-templates mode="flatxml_step1"/>
                    </xsl:copy>
                  </xsl:template>


                  <xsl:template match="*[local-name()='sections']//*[local-name()='terms']" mode="flatxml_step1" priority="2">
                  <!-- From:
                    <terms>
                    <term>...</term>
                    <term>...</term>
                    </terms>
                    To:
                    <section_terms>
                    <terms>...</terms>
                  </section_terms> -->
                  <xsl:element name="section_terms" namespace="https://www.metanorma.org/ns/bipm">
                  <!-- create empty element for case if first element isn't cross-align -->
                    <xsl:element name="empty" namespace="https://www.metanorma.org/ns/bipm">
                      <xsl:attribute name="cross-align">true</xsl:attribute>
                      <xsl:attribute name="element-number">empty_terms_<xsl:number/></xsl:attribute>
                    </xsl:element>
                    <xsl:call-template name="terms"/>
                  </xsl:element>
                </xsl:template>
                <xsl:template match="*[local-name()='sections']//*[local-name()='definitions']" mode="flatxml_step1" priority="2">
                  <xsl:element name="section_terms" namespace="https://www.metanorma.org/ns/bipm">
                    <xsl:call-template name="terms"/>
                  </xsl:element>
                </xsl:template>


                <!-- From:
                  <terms>
                  <term>...</term>
                  <term>...</term>
                  </terms>
                  To:
                  <terms/>
                  <term>...</term>
                <term>...</term>-->
                <!-- And
                  From:
                  <term>
                  <name>...</name>
                  <preferred>...</preferred>
                  <definition>...</definition>
                  <termsource>...</termsource>
                  </term>
                  To:
                  <term/>
                  <term_name>...</term_name>
                  <preferred>...</preferred>
                  <definition>...</definition>
                  <termsource>...</termsource>
                -->
                  <xsl:template match="jcgm:sections//jcgm:terms | jcgm:annex//jcgm:terms |
                  jcgm:sections//jcgm:term | jcgm:annex//jcgm:term" mode="flatxml_step1" name="terms">
                  <xsl:copy>
                    <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                    <xsl:attribute name="keep-with-next">always</xsl:attribute>
                    <xsl:call-template name="setCrossAlignAttributes"/>
                  </xsl:copy>
                  <xsl:apply-templates mode="flatxml_step1"/>
                </xsl:template>

                <!-- From:
                  <term><name>...</name></term>
                  To:
                <term><term_name>...</term_name></term> -->
                <xsl:template match="jcgm:term/jcgm:name" mode="flatxml_step1">
                  <xsl:element name="term_name" namespace="https://www.metanorma.org/ns/bipm">
                    <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                    <xsl:call-template name="setCrossAlignAttributes"/>
                    <xsl:apply-templates mode="flatxml_step1"/>
                  </xsl:element>
                </xsl:template>

                <!-- From:
                  <ul>
                  <li>...</li>
                  <li>...</li>
                  </ul>
                  To:
                  <ul/
                  <li>...</li>
                <li>...</li> -->
                <xsl:template match="jcgm:sections//jcgm:ul | jcgm:annex//jcgm:ul | jcgm:sections//jcgm:ol | jcgm:annex//jcgm:ol" mode="flatxml_step1">
                  <xsl:copy>
                    <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                    <xsl:attribute name="keep-with-next">always</xsl:attribute>
                    <xsl:call-template name="setCrossAlignAttributes"/>
                  </xsl:copy>
                  <xsl:apply-templates mode="flatxml_step1"/>
                </xsl:template>


                <!-- allow cross-align for element p, note, termsource, table, figure,  li (and set label)  -->
                <xsl:template match="jcgm:sections//jcgm:p |
                jcgm:sections//jcgm:note |
                jcgm:sections//jcgm:termsource |
                jcgm:sections//jcgm:li |
                jcgm:table |
                jcgm:figure |
                jcgm:annex//jcgm:p |
                jcgm:annex//jcgm:note |
                jcgm:annex//jcgm:termsource |
                jcgm:annex//jcgm:li" mode="flatxml_step1">
                <xsl:copy>
                  <xsl:apply-templates select="@*" mode="flatxml_step1"/>
                  <xsl:call-template name="setCrossAlignAttributes"/>
                  <xsl:choose>
                  <xsl:when test="*[local-name() = 'ul']/*[local-name() = 'li']">
                  <xsl:element name="ul" namespace="https://www.metanorma.org/ns/bipm">
                  <xsl:apply-templates mode="flatxml_step1"/>
                    </xsl:element>
                    </xsl:when>
                    <xsl:otherwise>
                  <xsl:apply-templates mode="flatxml_step1"/>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:copy>
              </xsl:template>


              <xsl:template name="setCrossAlignAttributes">
                <xsl:variable name="is_cross_aligned">
                  <xsl:call-template name="isCrossAligned"/>
                </xsl:variable>
                <xsl:if test="normalize-space($is_cross_aligned) = 'true'">
                  <xsl:attribute name="cross-align">true</xsl:attribute>
                  <!-- <xsl:attribute name="keep-with-next">always</xsl:attribute> -->
                </xsl:if>
                <xsl:call-template name="setElementNumber"/>
              </xsl:template>

              <!--
                Elements that should be aligned:
                - name of element presents in field align-cross-elements="clause note"
                - marked with attribute name
                - table/figure with attribute @multilingual-rendering = 'common' or @multilingual-rendering = 'all-columns'
                - marked with attribute cross-align
              -->
              <xsl:template name="isCrossAligned">
                <xsl:variable name="element_name" select="local-name()"/>
                <xsl:choose>
                  <!-- if element`s name is presents in array align_cross_elements -->
                  <xsl:when test="contains($align_cross_elements, concat('#',$element_name,'#'))">true</xsl:when>
                  <!-- if element has attribute name/bookmark -->
                  <xsl:when test="normalize-space(@name) != '' and @multilingual-rendering = 'name'">true</xsl:when>
                  <xsl:when test="($element_name = 'table' or $element_name = 'figure') and (@multilingual-rendering = 'common' or @multilingual-rendering = 'all-columns')">true</xsl:when>
                  <!-- element marked as cross-align -->
                  <xsl:when test="@multilingual-rendering='parallel'">true</xsl:when>
                  <xsl:otherwise>false</xsl:otherwise>
                </xsl:choose>
              </xsl:template>

              <!-- calculate element number in tree to find a match between documents -->
             <xsl:template name="setElementNumber">
                <xsl:variable name="element-number">
                  <xsl:choose>
                    <!-- if name set, then use it -->
                    <xsl:when test="@name and @multilingual-rendering = 'name'"><xsl:value-of select="@name"/></xsl:when>
                    <xsl:otherwise>
                      <xsl:for-each select="ancestor-or-self::*[ancestor-or-self::*[local-name() = 'sections' or local-name() = 'annex']]">
                        <xsl:value-of select="local-name()"/>
                        <xsl:choose>
                          <xsl:when test="local-name() = 'terms'"></xsl:when>
                          <xsl:when test="local-name() = 'sections'"></xsl:when>
                          <xsl:otherwise><xsl:number /></xsl:otherwise>
                        </xsl:choose>
                        <xsl:text>_</xsl:text>
                      </xsl:for-each>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:variable>
                <xsl:attribute name="element-number">
                  <xsl:value-of select="normalize-space($element-number)"/>
                </xsl:attribute>
              </xsl:template>
              <!-- ================================= -->
              <!-- ================================= -->
              <!-- End First step -->
              <!-- ================================= -->

          </xsl:stylesheet>
        XSLT
      end

      def flatxml_step2
        <<~XSLT
          <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
          xmlns:fo="http://www.w3.org/1999/XSL/Format"
          xmlns:jcgm="https://www.metanorma.org/ns/bipm"
          xmlns:bipm="https://www.metanorma.org/ns/bipm"
          xmlns:mathml="http://www.w3.org/1998/Math/MathML"
          xmlns:xalan="http://xml.apache.org/xalan"
          xmlns:exsl="http://exslt.org/common"
          xmlns:fox="http://xmlgraphics.apache.org/fop/extensions"
          xmlns:java="http://xml.apache.org/xalan/java"
          exclude-result-prefixes="java"
          version="1.0">

          <xsl:output method="xml" encoding="UTF-8" indent="no"/>

          <xsl:template match="@* | node()">
            <xsl:copy>
              <xsl:apply-templates select="@* | node()"/>
            </xsl:copy>
          </xsl:template>

          <xsl:template match="/*[local-name()='doc-container']/*[1]">
          <xsl:copy>
          <xsl:apply-templates   select="@*|node()"  mode="flatxml_step2"/>
          </xsl:copy>
          </xsl:template>

              <!-- ================================= -->
              <!-- Second step -->
              <!-- ================================= -->
              <xsl:template match="@*|node()" mode="flatxml_step2">
                <xsl:copy>
                  <xsl:apply-templates select="@*|node()" mode="flatxml_step2"/>
                </xsl:copy>
              </xsl:template>
              <!-- enclose elements after table/figure with @multilingual-rendering = 'common' and @multilingual-rendering = 'all-columns' in a separate element cross-align -->
              <xsl:template match="*[@multilingual-rendering = 'common' or @multilingual-rendering = 'all-columns']" mode="flatxml_step2" priority="2">
                <xsl:variable name="curr_id" select="generate-id()"/>
                <xsl:element name="cross-align" namespace="https://www.metanorma.org/ns/bipm">
                  <xsl:copy-of select="@element-number"/>
                  <xsl:copy-of select="@multilingual-rendering"/>
                  <xsl:copy-of select="@displayorder"/>
                  <xsl:copy-of select="."/>
                </xsl:element>
                <xsl:if test="following-sibling::*[(not(@cross-align) or not(@cross-align='true')) and preceding-sibling::*[@cross-align='true'][1][generate-id() = $curr_id]]">
                  <xsl:element name="cross-align" namespace="https://www.metanorma.org/ns/bipm">
                  <!-- <xsl:copy-of select="following-sibling::*[(not(@cross-align) or not(@cross-align='true')) and preceding-sibling::*[@cross-align='true'][1][generate-id() = $curr_id]][1]/@element-number"/> -->
                  <xsl:for-each select="following-sibling::*[(not(@cross-align) or not(@cross-align='true')) and preceding-sibling::*[@cross-align='true'][1][generate-id() = $curr_id]]">
                    <xsl:if test="position() = 1">
                      <xsl:copy-of select="@element-number"/>
                    </xsl:if>
                  <xsl:copy-of select="@displayorder"/>
                    <xsl:copy-of select="."/>
                  </xsl:for-each>
                </xsl:element>
              </xsl:if>
            </xsl:template>

            <xsl:template match="*[@cross-align='true']" mode="flatxml_step2">
              <xsl:variable name="curr_id" select="generate-id()"/>
              <xsl:element name="cross-align" namespace="https://www.metanorma.org/ns/bipm">
                <xsl:copy-of select="@element-number"/>
                  <xsl:copy-of select="@displayorder"/>
                <xsl:if test="local-name() = 'clause'">
                  <xsl:copy-of select="@keep-with-next"/>
                </xsl:if>
                <xsl:if test="local-name() = 'title'">
                  <xsl:copy-of select="@keep-with-next"/>
                </xsl:if>
                <xsl:copy-of select="@multilingual-rendering"/>
                <xsl:copy-of select="."/>

                <!-- copy next elements until next element with cross-align=true -->
                <xsl:for-each select="following-sibling::*[(not(@cross-align) or not(@cross-align='true')) and preceding-sibling::*[@cross-align='true'][1][generate-id() = $curr_id]]">
                  <xsl:copy-of select="."/>
                </xsl:for-each>
              </xsl:element>
            </xsl:template>

            <xsl:template match="*" mode="flatxml_step2">
                        <xsl:choose>
                                <xsl:when test="preceding-sibling::*[@cross-align='true'] and (not(@cross-align) or not(@cross-align='true'))"/>
                                <xsl:otherwise>
                                        <xsl:copy>
                                                <xsl:apply-templates select="@*|node()" mode="flatxml_step2"/>
                                        </xsl:copy>
                                </xsl:otherwise>
                        </xsl:choose>
                </xsl:template>

            <!-- ================================= -->
            <!-- End Second step -->
            <!-- ================================= -->

            </xsl:stylesheet>
        XSLT
      end

      def two_column
        <<~XSLT
          <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
          xmlns:fo="http://www.w3.org/1999/XSL/Format"
          xmlns:jcgm="https://www.metanorma.org/ns/bipm"
          xmlns:bipm="https://www.metanorma.org/ns/bipm"
          xmlns:mathml="http://www.w3.org/1998/Math/MathML"
          xmlns:xalan="http://xml.apache.org/xalan"
          xmlns:exsl="http://exslt.org/common"
          xmlns:fox="http://xmlgraphics.apache.org/fop/extensions"
          xmlns:java="http://xml.apache.org/xalan/java"
          exclude-result-prefixes="java"
          version="1.0">

          <xsl:output method="xml" encoding="UTF-8" indent="no"/>

          <xsl:template match="@* | node()">
            <xsl:copy>
              <xsl:apply-templates select="@* | node()"/>
            </xsl:copy>
          </xsl:template>

          <xsl:template match="//*[local-name()='doc-container'][1]">
            <xsl:copy>
            <xsl:apply-templates select="@* | node()" mode="multi_columns"/>
            </xsl:copy>
          </xsl:template>

          <xsl:template match="@* | node()" mode="multi_columns">
            <xsl:copy>
              <xsl:apply-templates select="@* | node()"  mode="multi_columns"/>
            </xsl:copy>
          </xsl:template>

          <xsl:template match="//*[local-name()='doc-container'][position() &gt; 1]">
          </xsl:template>

                  <!-- =================== -->
                  <!-- Two columns layout -->
                  <!-- =================== -->

                  <!-- <xsl:template match="*[@first]/*[local-name()='sections']//*[not(@cross-align) or not(@cross-align='true')]"/> -->

                  <xsl:template match="*[@first]/*[local-name()='sections']//*[local-name() = 'cross-align'] | *[@first]/*[local-name()='annex']//*[local-name() = 'cross-align']"  mode="multi_columns">
                          <xsl:variable name="element-number" select="@element-number"/>
                          <xsl:element name="cross-align" namespace="https://www.metanorma.org/ns/bipm">

                                          <xsl:copy-of select="@keep-with-next"/>
                                          <xsl:copy-of select="@displayorder"/>
                                                          <xsl:element name="align-cell" namespace="https://www.metanorma.org/ns/bipm">
                                                                          <xsl:copy-of select="@keep-with-next"/>
                                                                          <xsl:apply-templates select="." />
                                                          </xsl:element>
                                                          <xsl:variable name="keep-with-next" select="@keep-with-next"/>
                                                          <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">
                                                              <xsl:element name="align-cell" namespace="https://www.metanorma.org/ns/bipm">
                                                                                  <xsl:if test="$keep-with-next != ''">
                                                                                          <xsl:attribute name="keep-with-next"><xsl:value-of select="$keep-with-next"/></xsl:attribute>
                                                                                  </xsl:if>
                                                                                  <xsl:apply-templates select=".//*[local-name() = 'cross-align' and @element-number=$element-number]"/>
                                                                  </xsl:element>
                                                          </xsl:for-each>
                            </xsl:element>
                  </xsl:template>

                  <xsl:template match="*[local-name() = 'cross-align']" priority="3">
                          <xsl:apply-templates />
                  </xsl:template>

                  <!-- no display table/figure from slave documents if @multilingual-rendering="common" or @multilingual-rendering = 'all-columns' -->
                  <xsl:template match="*[@slave]//*[local-name()='table'][@multilingual-rendering= 'common']" priority="2"/>
                  <xsl:template match="*[@slave]//*[local-name()='table'][@multilingual-rendering = 'all-columns']" priority="2"/>
                  <xsl:template match="*[@slave]//*[local-name()='figure'][@multilingual-rendering = 'common']" priority="2"/>
                  <xsl:template match="*[@slave]//*[local-name()='figure'][@multilingual-rendering = 'all-columns']" priority="2"/>

                  <!-- for table and figure with @multilingual-rendering="common" -->
                  <!-- display only element from first document -->
                  <xsl:template match="*[@first]//*[local-name() = 'cross-align'][@multilingual-rendering = 'common']"  mode="multi_columns">
                                  <xsl:apply-templates />
                  </xsl:template>

                  <!-- for table and figure with @multilingual-rendering = 'all-columns' -->
                  <!-- display element from first document, then (after) from 2nd one, then 3rd, etc. -->
                    <xsl:template match="*[@first]//*[local-name() = 'cross-align'][@multilingual-rendering = 'all-columns']"  mode="multi_columns">
                          <xsl:variable name="element-number" select="@element-number"/>
                                  <xsl:apply-templates />
                                  <xsl:choose>
                                          <xsl:when test="local-name(*[@multilingual-rendering = 'all-columns']) = 'table'">
                                                  <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">
                                                          <xsl:for-each select=".//*[local-name() = 'table' and @element-number=$element-number]">
                                                                  <xsl:call-template name="table"/>
                                                          </xsl:for-each>
                                                  </xsl:for-each>
                                          </xsl:when>
                                          <xsl:when test="local-name(*[@multilingual-rendering = 'all-columns']) = 'figure'">
                                             <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">

                                                          <xsl:for-each select=".//*[local-name() = 'figure' and @element-number=$element-number]">
                                                                  <xsl:call-template name="figure"/>
                                                          </xsl:for-each>
                                                  </xsl:for-each>
                                          </xsl:when>
                                  </xsl:choose>
                  </xsl:template>

                  <!-- =========== -->
                  <!-- References -->
                  <xsl:template match="*[@first]//*[local-name()='references'][@normative='true']"  mode="multi_columns">
                  <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">
                      <xsl:element name="bookmark" namespace="https://www.metanorma.org/ns/bipm">
                                          <xsl:attribute name="id"><xsl:value-of select=".//*[local-name()='references'][@normative='true']/@id"/></xsl:attribute>
                                          </xsl:element>
                                  </xsl:for-each>
              <xsl:apply-templates  mode="multi_columns"/>
                  </xsl:template>

                  <xsl:template match="*[@first]//*[local-name()='references'][@normative='true']/*"  mode="multi_columns">
                          <xsl:variable name="number_"><xsl:number count="*"/></xsl:variable>
                          <xsl:variable name="number" select="number(normalize-space($number_))"/>
                          <xsl:element name="cross-align" namespace="https://www.metanorma.org/ns/bipm">
                                          <xsl:copy-of select="@displayorder"/>
                                                  <xsl:element name="align-cell" namespace="https://www.metanorma.org/ns/bipm">
                                                                  <xsl:apply-templates select="." />
                                                          </xsl:element>

                  <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">
                                                  <xsl:element name="align-cell" namespace="https://www.metanorma.org/ns/bipm">
                                                                                  <xsl:apply-templates select="(.//*[local-name()='references'][@normative='true']/*)[$number]"/>
                                                          </xsl:element>
                                                          </xsl:for-each>
                                  </xsl:element>
                  </xsl:template>

            <xsl:template match="*[@first]//*[local-name()='references'][not(@normative='true')]"  mode="multi_columns">
                             <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">
                                          <!--<bookmark id="{.//*[local-name()='references'][not(@normative='true')]/@id}"/>-->
                      <xsl:element name="bookmark" namespace="https://www.metanorma.org/ns/bipm">
                                          <xsl:attribute name="id"><xsl:value-of select=".//*[local-name()='references'][not(@normative='true')]/@id"/></xsl:attribute>
                                          </xsl:element>
                                  </xsl:for-each>
              <xsl:apply-templates  mode="multi_columns"/>
                  </xsl:template>

              <xsl:template match="*[@first]//*[local-name()='references'][not(@normative='true')]/*" mode="multi_columns">
              <xsl:variable name="number_"><xsl:number count="*"/></xsl:variable>
                          <xsl:variable name="number" select="number(normalize-space($number_))"/>
                          <xsl:element name="cross-align" namespace="https://www.metanorma.org/ns/bipm">
                                          <xsl:copy-of select="@displayorder"/>
                                                  <xsl:element name="align-cell" namespace="https://www.metanorma.org/ns/bipm">
                                                                  <xsl:apply-templates select="." />
                                                          </xsl:element>

                                      <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">

                                                  <xsl:element name="align-cell" namespace="https://www.metanorma.org/ns/bipm">
                                                                                  <xsl:apply-templates select="(.//*[local-name()='references'][not(@normative='true')]/*)[$number]"/>
                                                          </xsl:element>
                                                          </xsl:for-each>
                                  </xsl:element>
                  </xsl:template>
                  <!-- End of References -->

                  <xsl:template match="*[@first]//*[local-name()='annex']" mode="multi_columns">
              <xsl:variable name="number_"><xsl:number /></xsl:variable>
                          <xsl:variable name="number" select="number(normalize-space($number_))"/>
                              <xsl:for-each select="//*[local-name()='doc-container'][position() &gt; 1]">

                                          <!--<bookmark id="{(.//*[local-name()='annex'])[$number]/@id}"/>-->
                      <xsl:element name="bookmark" namespace="https://www.metanorma.org/ns/bipm">
                                          <xsl:attribute name="id"><xsl:value-of select=".//*[local-name()='annex'][$number]/@id"/></xsl:attribute>
                                          </xsl:element>
                                  </xsl:for-each>
              <xsl:apply-templates mode="multi_columns"/>
            </xsl:template>

                  <!-- =================== -->
                  <!-- End Two columns layout -->
                  <!-- =================== -->

          </xsl:stylesheet>
        XSLT
      end

      def initialize(options)
        options[:align_cross_elements] ||= %w(note p)
        @align_cross_elements = " #{options[:align_cross_elements].join(' ')} "
        @flavor = options[:flavor]
        @outdir = options[:outdir]
        @converter_opt = options[:converter_options]
      end

      def htmlconv
        x = Asciidoctor.load nil, backend: Util::taste2flavor(@flavor)
        x.converter.html_converter(@converter_opt)
      end

      def to_bilingual(input)
        presxml = Nokogiri::XML(input)
        doc_first_input = xmldoc(presxml.at("//xmlns:doc-container[1]"))
        doc_first_step1 =
          Nokogiri::XSLT(flatxml_step1("first", @align_cross_elements))
            .transform(doc_first_input)
        doc_first = Nokogiri::XSLT(flatxml_step2).transform(doc_first_step1)
        docs_slave_input = presxml.xpath("//xmlns:doc-container[position() > 1]")
          .map do |x|
          xmldoc(x)
        end
        docs_slave_step1 = docs_slave_input.map do |x|
          Nokogiri::XSLT(flatxml_step1("slave",
                                       @align_cross_elements)).transform(x)
        end
        docs_slave = docs_slave_step1.map do |x|
          Nokogiri::XSLT(flatxml_step2).transform(x)
        end
        doc = Nokogiri::XML("<root xmlns='http://metanorma.org'/>")
        doc.root << doc_first.root
        docs_slave.each { |x| doc.root << x.root }
        ret = Nokogiri::XSLT(two_column).transform(doc)
        presxml.at("//xmlns:doc-container[1]").replace(ret.root.children)
        to_xml(presxml)
      end

      def to_html(presxml)
        xml = Nokogiri::XML(File.read(presxml))
        doc = xml.at("//xmlns:doc-container[1]/*")
        # will need to concatenate preface if present
        out = File.join(@outdir, "collection.bilingual.presentation.xml")
        File.open(out, "w:utf-8") { |f| f.write to_xml(doc) }
        htmlconv.convert(out)
      end
    end
  end
end
