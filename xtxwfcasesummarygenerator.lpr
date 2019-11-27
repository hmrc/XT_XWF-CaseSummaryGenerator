library xtxwfcasesummarygenerator;
{
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
}
{$mode Delphi}{$H+}  // this compiler directive ensures strings are not truncated at 255

uses
  Classes, XT_API, windows, sysutils, contnrs, md5;

// This particular type declaration is used by the hashlist only
type
  PData = ^TData;
  TData = record
    FName: String;
    FCount: Int64;
  end;

  const
    BufEvdNameLen=256;
var
  // These are global vars
  MainWnd                  : THandle;
  CurrentVolume            : THandle;
  slCaseTypesSummary       : TStringList;
  slJustTheFileCategories  : TStringList;
  HashList                 : TFPHashList;
  TotalDataInBytes         : Int64;
  itemcount                : integer;
  ItemsReported            : Integer;
  deleteditemcount         : integer;
  FolderCount              : integer;
  infoflag_Error           : integer;
  infoflag_NotVerified     : integer;
  infoflag_TooSmall        : integer;
  infoflag_TotallyUnknown  : integer;
  infoflag_Confirmed       : integer;
  infoflag_NotConfirmed    : integer;
  infoflag_NewlyIdentified : integer;
  infoflag_MisMatch        : integer;

  // Evidence name is global for later filesave by name
  pBufEvdName              : array[0..BufEvdNameLen-1] of WideChar;

// The first call needed by the X-Tension API. Must return 1 for the X-Tension to continue.
function XT_Init(nVersion, nFlags: DWord; hMainWnd: THandle; lpReserved: Pointer): LongInt; stdcall; export;
begin
  // Just make sure everything is initialised
  itemcount                := 0;
  TotalDataInBytes         := 0;
  ItemsReported            := 0;
  deleteditemcount         := 0;
  FolderCount              := 0;
  infoflag_Error           := 0;
  infoflag_NotVerified     := 0;
  infoflag_TooSmall        := 0;
  infoflag_TotallyUnknown  := 0;
  infoflag_Confirmed       := 0;
  infoflag_NotConfirmed    := 0;
  infoflag_NewlyIdentified := 0;
  infoflag_MisMatch        := 0;
  FillChar(pBufEvdName, SizeOf(pBufEvdName), $00);
  // Check XWF is ready to go. 1 is normal mode, 2 is thread-safe. Using 1 for now
  if Assigned(XWF_OutputMessage) then
  begin
    Result := 1; // lets go
    MainWnd:= hMainWnd;
  end
  else Result := -1; // stop
end;

// Used by the button in the X-Tension dialog to tell the user about the X-Tension
// Must return 0
function XT_About(hMainWnd : THandle; lpReserved : Pointer) : Longword; stdcall; export;
begin
  result := 0;
  MessageBox(MainWnd,  ' Case Summariser X-Tension for X-Ways Forensics. ' +
                       ' To be executed only via the RVS dialog of XWF v18.9 or higher. ' +
                       ' Developed by HMRC, Crown Copyright (c) 2019.' +
                       ' Intended use : to create HTML report for each evidence object, totalling the number of each file category for the case.'
                      ,'Case Summariser v0.1 Alpha', MB_ICONINFORMATION);
end;
// Returns a human formatted version of the time
function TimeStampIt(TheDate : TDateTime) : string; stdcall; export;
begin
  result := FormatDateTime('DD/MM/YYYY HH:MM:SS', TheDate);
end;

// Renders integers representing bytes into string format, e.g. 1MiB, 2GiB etc
function FormatByteSize(const bytes: QWord): string;  stdcall; export;
var
  B: byte;
  KB: word;
  MB: QWord;
  GB: QWord;
  TB: QWord;
begin

  B  := 1;         // byte
  KB := 1024 * B;  // kilobyte
  MB := 1024 * KB; // megabyte
  GB := 1024 * MB; // gigabyte
  TB := 1024 * GB; // terabyte

  if bytes > TB then
    result := FormatFloat('#.## TiB', bytes / TB)
  else
    if bytes > GB then
      result := FormatFloat('#.## GiB', bytes / GB)
    else
      if bytes > MB then
        result := FormatFloat('#.## MiB', bytes / MB)
      else
        if bytes > KB then
          result := FormatFloat('#.## KiB', bytes / KB)
        else
          result := FormatFloat('#.## bytes', bytes) ;
end;

// Gets the case name, and currently selected evidence object, and the image size
// and stores as a header for writing to HTML output later
// Returns true on success. False otherwise.
function GetEvdData(hEvd : THandle) : boolean; stdcall; export;
const
  BufLen=256;
var
  Buf            : array[0..BufLen-1] of WideChar;
  pBufCaseName   : array[0..Buflen-1] of WideChar;
  CaseProperty, EvdSize, intEvdName : Int64;

begin
  result := false;
  // Get the case name, to act as the title in the output file, and store in pBufCaseName
  // XWF_CASEPROP_TITLE = 1, thus that value passed
  CaseProperty := -1;
  CaseProperty := XWF_GetCaseProp(nil, 1, @pBufCaseName[0], Length(pBufCaseName));

  // Get the item size of the evidence object. 16 = Evidence Total Size
  EvdSize := -1;
  EvdSize := XWF_GetEvObjProp(hEvd, 16, nil);

  // Get the evidence object name and store in pBufEvdName. 7 = object name
  intEvdName := -1;
  intEvdName := XWF_GetEvObjProp(hEvd, 7, @pBufEvdName[0]);

  try
    // This is the holding store to store every file category for every item
    // This is the list to help create the summary output
    // At this point we just add the case and evidence object data as a header
    // for writing later into the HTML output

    slCaseTypesSummary.Add('<html><head><h2>Report generated: ' + TimeStampIt(Now) + ' </h2></head><body>');

    if CaseProperty > -1 then slCaseTypesSummary.Add('<h3>X-ways Forensics Case Name: '+ pBufCaseName + '</h3>');
    if intEvdName   > -1 then slCaseTypesSummary.Add('<h3>Evidence Object Name: ' + pBufEvdName + '</h3>');
    if EvdSize      > -1 then slCaseTypesSummary.Add('<h3>Evidence Object Size: ' + FormatByteSize(EvdSize) + '</h3>');

    slCaseTypesSummary.Add('<p>The figures below refer to "file items" within this evidential object. ' +
                           'They may represent actual, complete, "files" such as "hello.doc" or they may be parts of a file, ' +
                           'or they may be information about a file, or virtual files created from a file <strong>about</strong> a file ' +
                           '(e.g a human readable version of Skype or WhatsApp database file), or files from within other files ' +
                           '(e.g "hello.doc from "MyFiles.zip"). The figures are provided only as a means to quantify case volumetrics ' +
                           'and should not be taken as an exacting statement of the "the number of files on the device". ' +
                           'The figures will seldom ever be equal to the exact number of "files" as listed by the operating system ' +
                           'on the original device and different forensic tools work in different ways. These figures are from X-Ways Forensics </p>');

    slCaseTypesSummary.Add('<p>Figures include theoretically <strong>legible</strong> undeleted files (illegible undeleted files, excluded). </p>');

    slCaseTypesSummary.Add('<table border="1">');
  finally
    lstrcpyw(Buf, 'Output headers built : OK.');
    XWF_OutputMessage(@Buf[0], 0);
    result := true;
  end;
end;

// Examines each item in the selected evidence object. The "type category" of the item
// is then added to a string list for traversal later. Must return 0! -1 if fails.
function XT_ProcessItem(nItemID : LongWord; lpReserved : Pointer) : integer; stdcall; export;
const
  BufLen=256;
var
  ItemSize     : Int64;
  lpTypeDescr  : array[0..Buflen-1] of WideChar;
  infoDeletion, infoFolderType    : Int64;
  itemtypeinfoflag : integer;
  successDeletionFlags, successFolderFlags : boolean;

begin
  ItemSize := -1;
  infoDeletion := -1;
  infoFolderType := -1;
  successFolderFlags := false;
  successDeletionFlags := false;

  // Make sure buffer is empty and filled with zeroes
  FillChar(lpTypeDescr, Length(lpTypeDescr), #0);

  // Get the size of the item
  ItemSize := XWF_GetItemSize(nItemID);
  if ItemSize > 0 then inc(TotalDataInBytes, ItemSize);

  // For every item, add its file category (e.g. "Documents", "Spreadhseets" etc) to a list
  // $40000000 is the value to pass to get the category, instead of the type
  // We traverse this later to tally the count for each
  // Also, we get the file "type status" :
  // 0=not verified,
  // 1=too small,
  // 2=totally unknown,
  // 3=confirmed,
  // 4=not confirmed,
  // 5=newly identified,
  // 6 (v18.8 and later only)=mismatch detected.
  // -1 means error.
  // *** Too small files are not added. ***
  itemtypeinfoflag := XWF_GetItemType(nItemID, lpTypeDescr, Length(lpTypeDescr) or $40000000);

  { API docs state that the first byte in the buffer should be empty on failure to lookup category
    So if the buffer is empty, no text category could be retrieved. Otherwise, classify it. }
  if lpTypeDescr<> #0 then
  begin
    if itemtypeinfoflag = 0 then       // Not verified
    begin
      inc(infoflag_NotVerified,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = 1 then      // Too small, less than 8 bytes
    begin
      inc(infoflag_TooSmall,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = 2 then      // Totally Unknown\Unverified
    begin
      inc(infoflag_TotallyUnknown,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = 3 then      // Confirmed file
    begin
      inc(infoflag_Confirmed,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = 4 then      // Not confirmed file
    begin
      inc(infoflag_NotConfirmed,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = 5 then      // Newly identified
    begin
      inc(infoflag_NewlyIdentified,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = 6 then      // Mis-match - extension does not match signature
    begin
      inc(infoflag_MisMatch,1);
      slJustTheFileCategories.Add(WideCharToString(@lpTypeDescr[0]));
      inc(ItemsReported, 1);
    end
    else
    if itemtypeinfoflag = -1 then    // XWF had an error running XWF_GetItemType
    begin
      inc(infoflag_Error,1);
    end;
  end
  else
  // If the buffer is empty, null terminated, XWF could not recover a category text value.
  // This should be very rare, because even "Other\Unknown" types are represented in XWF,
  // and returned as "Other\Unknown".
    begin
      slJustTheFileCategories.Add('No category entry - not even "Unknown"');
      inc(ItemsReported, 1);
   end;

  // XWF_ITEM_INFO_DELETION refers to value '4'.
  { 0 = existing item, so we not interested in that for the purposes of identifiying deleted items
    >0 = not existing (which is all of the following:)
    1 = previously existing, possibly recoverable
    2 = previously existing, first cluster overwritten or unknown
    3 = renamed/moved, possibly recoverable
    4 = renamed/moved, first cluster overwritten or unknown
    5 = carved file (since v19.3 SR-3, used to be 1)
  }

  // Work out if the item is a deleted file or not
  infoDeletion := XWF_GetItemInformation(nItemID, XWF_ITEM_INFO_DELETION, @successDeletionFlags);
  if successDeletionFlags then // if XWF_GetItemInformation could complete OK
  begin
    if (infoDeletion > 0) then // record the item as a deleted file
    begin
      inc(deleteditemcount, 1);
    end;
  end
  else inc(infoflag_Error,1);  // XWF_GetItemInformation failed with an error

  // Work out if the item is a folder or not
  infoFolderType := XWF_GetItemInformation(nItemID, XWF_ITEM_INFO_FLAGS, @successFolderFlags);
  if (infoFolderType and 1) <> 0 then  // is a directory
    begin
      inc(FolderCount, 1);
    end;
  // The ALL IMPORTANT 0 return value!!
  result := 0;
end;

// called immediately for a volume when volume snapshot refinement or some other action starts
// This is used for every evidence object selected when executed via RVS and for each item
// XT_ProcessItem is resulted
function XT_Prepare(hVolume, hEvidence : THandle; nOpType : DWord; lpReserved : Pointer) : integer; stdcall; export;
const
  BufLen=256;
var
  outputmessage  : array[0..MAX_PATH] of WideChar;
  Buf            : array[0..Buflen-1] of WideChar;
  success        : boolean;

begin
  itemcount                := 0;
  ItemsReported            := 0;
  FolderCount              := 0;
  deleteditemcount         := 0;
  infoflag_Error           := 0;
  infoflag_Error           := 0;
  infoflag_NotVerified     := 0;
  infoflag_TooSmall        := 0;
  infoflag_TotallyUnknown  := 0;
  infoflag_Confirmed       := 0;
  infoflag_NotConfirmed    := 0;
  infoflag_NewlyIdentified := 0;
  infoflag_MisMatch        := 0;

  // Create two global stringlists for holidng the item category values for each item
  // and then the one to render as HTML containing the summarised results
  slJustTheFileCategories := TStringList.Create;
  slCaseTypesSummary      := TStringList.Create;
  // Nad now create a global hashlist for counting all the occurances of "Pictures", "Internet", etc
  HashList                := TFPHashlist.Create;

  if nOpType <> 1 then
  begin
    MessageBox(MainWnd, 'Advisory: ' +
                        ' Please execute this X-Tension via the RVS (F10) option only' +
                        ' and apply it to your selected evidence object(s).'
                       ,'Case Summariser v1.0 Beta', MB_ICONINFORMATION);
    // Tell XWF to abort if the user attempts another mode of execution, by returning -3
    result := -3;
  end
  else
    begin
      // We need our X-Tension to return 0x01, 0x08, 0x10, and 0x20, depending on exactly what we want
      // We can change the result using or combinations as we need, as follows:
      // Call XT_ProcessItem for each item in the evidence object : (0x01)  : XT_PREPARE_CALLPI
      // and to target zero byte files too                        : (0x08)  : XT_PREPARE_TARGETZEROBYTEFILES
      // and to target folders                                    : (0x10)  : XT_PREPARE_TARGETDIRS
      // and to target omitted files                              : (0x20)  : XT_PREPARE_DONTOMIT
      // If we ever want it to run in dumb mode, change result to zero, and uncommented for loop at bottom

      result := XT_PREPARE_CALLPI or XT_PREPARE_TARGETDIRS; // or XT_PREPARE_TARGETZEROBYTEFILES or XT_PREPARE_DONTOMIT;

      // Get the total item count for this particular evidence object, regardless of exclusions
      itemcount     := XWF_GetItemCount(nil);
      outputmessage := 'Total item count inc folders : ' + IntToStr(itemcount);
      lstrcpyw(Buf, outputmessage);
      XWF_OutputMessage(@Buf[0], 0);

      // Now gather the evidence object metadata and build the headers for the HTML output
      success := GetEvdData(hEvidence);
      if success then
      begin
        outputmessage := 'Starting analysis of evidence object...';
        lstrcpyw(Buf, outputmessage);
        XWF_OutputMessage(@Buf[0], 0);
      end
      else
      begin
        outputmessage := 'Unable to start analysis of evidence object...ERROR';
        lstrcpyw(Buf, outputmessage);
        XWF_OutputMessage(@Buf[0], 0);
      end;
      // With the above settings, XWF will intelligently skip certain items due to,
      // for example, first cluster not known etc. In the future, if we need to
      // change it to do all items regardless, we can change the result
      // of this function to 0 and then uncomment the "for loop" code below.
      // Then XWF will call XT_ProcessItem for every item in the evidence object
      // even if the file item is total nonsensical data.
      {
      for i := 0 to itemcount -1 do
      begin
        XT_ProcessItem(i, nil);
      end;
      }
    end;
end;

// Takes the stringlist of file categories and works out how many times each one appears
// using hashlists. Returns true on success.  False on failure.
function ComputeMetrics(slFileCategories : TStringList) : boolean; stdcall; export;
var
  j, index  : integer;
  Hash      : ShortString;
  Data      : PData;
begin
  // MD5 is the fastest and perfectly fine for this task.
  result := false;
  for j := 0 to slFileCategories.Count - 1 do
  begin
    Hash  := MD5Print(MD5String(slFileCategories.Strings[j]));
    Index := HashList.FindIndexOf(Hash);
    if Index = -1 then
    begin
      New(Data);
      Data^.FName  := slFileCategories.Strings[j];
      Data^.FCount := 1;
      HashList.Add(Hash, Data);
    end
    else
      Inc(TData(HashList[Index]^).FCount);
  end;
  result := true;
end;

// finish the output and save to the HTML footers. Returns true on success. False otherwise
function BuildCaseTypeSummary(HL : TFPHashlist) : boolean; stdcall; export;
const
  Buflen=256;
  PostFixFilename = '-CaseSummary.html';
var
  k : integer;
  Buf, outputpathmessage : array[0..Buflen-1] of WideChar;
  OutputFolder : string;
begin
  result       := false;
  OutputFolder := IncludeTrailingPathDelimiter(GetUserDir + 'Documents');

  for k := 0 to HL.Count - 1 do
  begin
    slCaseTypesSummary.Add('<tr><td>'+TData(HL.Items[k]^).FName + '</td><td>    ' + IntToStr(TData(HL.Items[k]^).FCount)+'</td></tr>');
  end;
  slCaseTypesSummary.Add('</table>');
  slCaseTypesSummary.Add('<p>'+ IntToStr(itemcount) + ' items exist in the case overall (including ' + IntToStr(FolderCount) + ' folders). Of those, it was possible to report on '+ IntToStr(ItemsReported) + ' items. ' + IntToStr(itemcount-ItemsReported) + ' illegible, omitted, or zero-byte items were not reported.</p>');

  slCaseTypesSummary.Add('<p>'+ IntToStr(deleteditemcount) + ' items have a deleted status of some kind and may not be legible. </p>');

  slCaseTypesSummary.Add('<p>'+ IntToStr(TotalDataInBytes) + ' total bytes of data comprise the files reported on (' + FormatByteSize(TotalDataInBytes)+ '). This figure can exceed the size of the original evidence ' +
                         'due to extracted objects, decompression, the inclusion of free space fragments etc. Equally, the figure can be much lower because the figure represents data belonging to file items, not overall disk size which may not all have been allocated to a filesystem.</p>');

  slCaseTypesSummary.Add('<p><strong>Legend</strong> (further information can be found at http://www.x-ways.com/winhex/manual.pdf under section "Type Status" and "Category"):</p>');
  slCaseTypesSummary.Add('<ul>');
  slCaseTypesSummary.Add('<li>"Errors" : X-Ways Forensics was unable to process or lookup any information about a file item.</li>');
  slCaseTypesSummary.Add('<li>"Confirmed" : If the signature matches the extension according to the database, the status is "confirmed". </li>' +
                         '<li>"Not Confirmed" : If the extension is referenced in the database, yet the signature actually found in the file is unknown, the status is "not confirmed". </li>' +
                         '<li>"Mismatch Detected" If the signature matches a certain file type in the database, however the extension matches a different file type, the status is "mismatch detected".</li>');
  slCaseTypesSummary.Add('</ul>');
  slCaseTypesSummary.Add('<p><table border="1">');
  slCaseTypesSummary.Add('<tr><td>Errors : </td><td>'              + IntToStr(infoflag_Error)          + '</td></tr>');
  slCaseTypesSummary.Add('<tr><td>Confirmed : </td><td> '          + IntToStr(infoflag_Confirmed)      + '</td></tr>');
  slCaseTypesSummary.Add('<tr><td>Not Confirmed : </td><td> '      + IntToStr(infoflag_NotConfirmed)   + '</td></tr>');
  slCaseTypesSummary.Add('<tr><td>Mismatch detected : </td><td> '  + IntToStr(infoflag_MisMatch)       + '</td></tr>');
  slCaseTypesSummary.Add('</p></table>');
  slCaseTypesSummary.Add('</body>');

  lstrcpyw(Buf, 'Saving results and freeing resources...');
  XWF_OutputMessage(@Buf[0], 0);

  try
    slCaseTypesSummary.SaveToFile(OutputFolder + pBufEvdName + PostFixFilename);
    outputpathmessage := 'Result saved to : ' + OutputFolder + pBufEvdName + PostFixFilename;
    lstrcpyw(Buf, @outputpathmessage);
    XWF_OutputMessage(@Buf[0], 0);
  finally
    result := true;
  end;
end;

// Called after all items in the evidence objects have been itterated.
// Returns -1 on failure. 0 on success.
function XT_Finalize(hVolume, hEvidence : THandle; nOpType : DWord; lpReserved : Pointer) : integer; stdcall; export;
const
  Buflen=256;
var
  successMetrics, successCaseSummary : boolean;
  Buf : array[0..Buflen-1] of WideChar;

begin
  // Now that all the items have been iterated by XWF, traverse the stringlist
  // of all the file categories, and work out how many of each there are
  successMetrics := ComputeMetrics(slJustTheFileCategories);
  if successMetrics then
  begin
    lstrcpyw(Buf, 'Metrics for evidence object computed OK...');
    XWF_OutputMessage(@Buf[0], 0);
  end
  else
  begin
    lstrcpyw(Buf, 'Metrics for evidence object were not computed properly: ERROR...');
    XWF_OutputMessage(@Buf[0], 0);
  end;

  // Now that the count of file categories has been computed, finish the output
  // and save to the HTML footers
  successCaseSummary := BuildCaseTypeSummary(HashList);
  if successCaseSummary then
  begin
    lstrcpyw(Buf, 'Summary report for evidence object computed and saved OK...');
    XWF_OutputMessage(@Buf[0], 0);
  end
  else
  begin
    lstrcpyw(Buf, 'Summary report for evidence object were not properly computed and were not saved : ERROR...');
    XWF_OutputMessage(@Buf[0], 0);
  end;

  // Now free all the lists that were used for this evidence object
  slCaseTypesSummary.free;
  slJustTheFileCategories.free;
  HashList.free;
  lstrcpyw(Buf, '==============.');
  XWF_OutputMessage(@Buf[0], 0);
  result := 0;
end;

// called just before the DLL is unloaded to give XWF chance to dispose any allocated memory,
// Should return 0.
function XT_Done(lpReserved: Pointer) : integer; stdcall; export;
begin
  result := 0;
end;


exports
  XT_Init,
  XT_About,
  XT_Prepare,
  XT_ProcessItem,
  XT_Finalize,
  XT_Done,
  // The following may not be exported in future versions
  TimeStampIt,
  FormatByteSize,
  ComputeMetrics;
begin

end.



