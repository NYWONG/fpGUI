{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (C) 2006 - 2010 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      BMP format image parser
}


unit fpg_imgfmt_bmp;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpg_main,
  fpg_base;

procedure ReadImage_BMP(img: TfpgImage; bmp: Pointer; bmpsize: longword);
function  LoadImage_BMP(const AFileName: String): TfpgImage;
function  CreateImage_BMP(bmp: Pointer; bmpsize: longword): TfpgImage;


implementation


function CreateImage_BMP(bmp: Pointer; bmpsize: longword): TfpgImage;
begin
  Result := TfpgImage.Create;
  ReadImage_BMP(Result, bmp, bmpsize);
end;

function LoadImage_BMP(const AFileName: String): TfpgImage;
var
  AFile: file of char;
  AImageData: Pointer;
  AImageDataSize: integer;
begin
  Result := nil;
  if not FileExists(AFileName) then
    Exit; //==>

  AssignFile(AFile, AFileName);
  FileMode := fmOpenRead; // read-only
  Reset(AFile);
  AImageDataSize := FileSize(AFile);
  AImageData := nil;
  GetMem(AImageData, AImageDataSize);
  try
    BlockRead(AFile, AImageData^, AImageDataSize);
    Result := TfpgImage.Create;
    ReadImage_BMP(Result, AImageData, AImageDataSize);
  finally
    CloseFile(AFile);
    FreeMem(AImageData);
  end;
end;


type
  // Windows BMP format description:
  // Below is the exact order how how information is stored in a BMP file.

  TBMPHeaderRec = packed record
    signature: word;
    filesize: longword;
    reserved: longword;
    dataoffset: longword;
  end;
  PBMPHeaderRec = ^TBMPHeaderRec;

  TBMPInfoHeaderRec = packed record
    headersize: longword; // = 40
    Width: longword;
    Height: longword;
    planes: word;
    bitcount: word;
    compression: longword;
    imagesize: longword; // bytes in the image data (after the color table)
    XpixelsPerM: longword;
    YpixelsPerM: longword;
    ColorsUsed: longword;
    ColorsImportant: longword;
  end;
  PBMPInfoHeaderRec = ^TBMPInfoHeaderRec;

  // Then follows the Color Table if bitcount <= 8

  TBMPColorTableRec = packed record
    red: byte;
    green: byte;
    blue: byte;
    reserved: byte;
  end;

 // Then follows the image data
 // Every line padded to 32 bits
 // The lines stored bottom-up


procedure ReadImage_BMP(img: TfpgImage; bmp: Pointer; bmpsize: longword);
var
  bh: PBMPHeaderRec;
  ih: PBMPInfoHeaderRec;
  p: PByte;
  ppal: plongword;
  pcol: Plongword;
  palsize: integer;
  pdata: PByte;
  b: byte;
  bit: byte;
  bcnt: byte;
  linecnt: integer;
  pixelcnt: integer;
  pdest: Plongword;
  depth: integer;

  function GetPalColor(cindex: longword): longword;
  var
    pc: Plongword;
  begin
    pc     := ppal;
    Inc(pc, cindex);
    Result := pc^;
  end;

begin
  if img = nil then
    Exit; //==>

  img.FreeImage;

  p         := bmp;
  PByte(bh) := p;
  ppal      := nil;
  if bh^.filesize <> bmpsize then
    Exit; //==>

  pdata := bmp;
  Inc(pdata, bh^.dataoffset);
  Inc(p, SizeOf(TBMPHeaderRec));
  PByte(ih) := p;
  depth := ih^.bitcount;

  if depth > 1 then
    img.AllocateImage(32, ih^.Width, ih^.Height)// color image
  else
  begin
    img.AllocateImage(1, ih^.Width, ih^.Height);
    img.AllocateMask;
  end;

  //Writeln('width: ',img.width,' height: ',img.height,' depth: ',depth);
  //Writeln('compression: ',ih^.compression);

  Inc(p, SizeOf(TBMPInfoHeaderRec));

  if ih^.bitcount <= 8 then
  begin
    // reading color palette
    case ih^.bitcount of
      1: palsize := 2;
      4: palsize := 16;
      else
        palsize  := 256;
    end;

    GetMem(ppal, palsize * SizeOf(longword));

    pcol     := ppal;
    pixelcnt := 0;
    while (p) < (pdata) do
    begin
      pcol^ := (LongWord(p[3]) shl 24) + (LongWord(p[2]) shl 16) + (LongWord(p[1]) shl 8) + LongWord(p[0]);
      Inc(pcol);
      inc(p, 4);
      Inc(pixelcnt);
    end;
  end;

  pdest := img.ImageData;
  Inc(pdest, img.Width * (img.Height - 1));  // bottom-up line order
  p := bmp;
  Inc(p, bh^.dataoffset);

  // reading the data...
  case ih^.bitcount of
    1:
    begin
      // direct line transfer
      //writeln('reading 1-bit color bitmap');
      linecnt := 0;
      bcnt := img.Width div 32;
      if (img.Width and $1F) > 0 then
        Inc(bcnt);

      pdest := img.ImageData;
      Inc(pdest, bcnt * (img.Height - 1));  // bottom-up line order
      repeat
        move(p^, pdest^, bcnt * 4);
        Inc(p, bcnt * 4);
        Dec(pdest, bcnt);
        Inc(linecnt);
      until linecnt >= img.Height;

      //Writeln(linecnt,' lines loaded.');
      move(img.ImageData^, img.MaskData^, img.ImageDataSize);
      img.Invert;
    end;

    4:
    begin
      //writeln('reading 4-bit color');
      linecnt := 0;
      repeat
        // parse one line..
        bit      := 0;
        pixelcnt := 0;
        bcnt     := 0;
        repeat
          if bit = 0 then
            b := (p^ shr 4) and $0F
          else
          begin
            b := p^ and $0F;
            Inc(p);
            Inc(bcnt);
          end;

          pdest^ := GetPalColor(b);
          Inc(pdest);
          Inc(pixelcnt);
          bit := bit xor 1;
        until pixelcnt >= img.Width;

        while (bcnt mod 4) <> 0 do
        begin
          Inc(bcnt);
          Inc(p);
        end;

        Inc(linecnt);
        Dec(pdest, img.Width * 2);  // go to next line
      until linecnt >= img.Height;
    end;

    8:
    begin
      //writeln('reading 8-bit color');
      linecnt := 0;
      repeat
        // parse one line..
        pixelcnt := 0;
        repeat
          pdest^ := GetPalColor(p^);
          Inc(p);
          Inc(pdest);
          Inc(pixelcnt);
        until pixelcnt >= img.Width;

        while (pixelcnt mod 4) <> 0 do
        begin
          Inc(pixelcnt);
          Inc(p);
        end;

        Inc(linecnt);
        Dec(pdest, img.Width * 2);  // go to next line
      until linecnt >= img.Height;
    end;

    24:
    begin
      //writeln('reading truecolor');
      linecnt := 0;
      repeat
        // parse one line..
        pixelcnt := 0;
        repeat
          pdest^ := p^;
          Inc(p);
          pdest^ := pdest^ or (longword(p^) shl 8);
          Inc(p);
          pdest^ := pdest^ or (longword(p^) shl 16);
          Inc(p);
          Inc(pdest);
          Inc(pixelcnt);
        until pixelcnt >= img.Width;

        pixelcnt := img.Width * 3;
        while (pixelcnt mod 4) <> 0 do
        begin
          Inc(pixelcnt);
          Inc(p);
        end;

        Inc(linecnt);
        Dec(pdest, img.Width * 2);  // go to next line
      until linecnt >= img.Height;
    end;
    else
      writeln('Unsupported BMP format!');
  end;

  if ppal <> nil then
    FreeMem(ppal);

  img.UpdateImage;
end;

end.

