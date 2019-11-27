# XT_XWF-CaseSummaryGenerator (An X-Tension to Generate Summary Information)

###  *** Requirements ***
  This X-Tension is designed for use only with X-Ways Forensics
  This X-Tension is designed for use only with v18.9 or later (due to file category lookup).
  This X-Tension is not designed for use on Linux or OSX platforms.
  There is a compiled 32 and 64 bit version of the X-Tension to be used with the
  corresponding version of X-Ways Forensics.

###  *** Usage Disclaimer ***
  This X-Tension is a Proof-Of-Concept Alpha level prototype, and is not finished.
  It has known limitations. You are NOT advised to use it, yet, for any evidential
  work for criminal courts.

###  *** Functionality Overview ***
  The X-Tension uses the "Type Category" values of a case (e.g. "Spreadhseets",
  "Pictures" etc) and not the file type values (doc, docx etc) to rapidly generate
  HTML reports to allow a volume summary to be generated and disclosed to other
  relevant parties such as legal teams, investigations teams and so on.
  e.g. "10K Pictures", "20K E-Mails"

  It should be executed via the "Refine Volume Snapshot" (RVS, F10) of X-Ways Forensics
  The X-Tension works by reporting the assigned category of each item.
  The category of each item is added to a global stringlist, potentially containing
  thousands of values. After all the items are counted for a given evidence object,
  the stringlist is then itterated using a fast hashlist to count the occurences
  of each category.

  On completion of that stage, the results are saved to a HTML file named after the
  evidence object, tabulating the results. It then moves to the next until all are processed.

  The output is saved to the users "Documents" folder automatically, e.g. C:\Users\Joe\Documents.

  Current benchmarks have seen test cases with 1 million items reported in 8 seconds.

###  TODOs
   // TODO Ted Smith : Finish and refine user manual

  *** License ***
  This code is open source software licensed under the [Apache 2.0 License]("http://www.apache.org/licenses/LICENSE-2.0.html")
  and The Open Government Licence (OGL) v3.0.
  (http://www.nationalarchives.gov.uk/doc/open-government-licence and
  http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

###  *** Collaboration ***
  Collaboration is welcomed, particularly from Delphi or Freepascal developers.
  This version was created using the Lazarus IDE v2.0.4 and Freepascal v3.0.4.
  (www.lazarus-ide.org)    