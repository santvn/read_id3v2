 function tag = read_id3v2(file_name)
%read_id3v2 - Reader for the ID3 tag version 2 of MP3 files
%    This function reads the ID3 tag header for MP3 files.
%    The versions supported are 2.2, 2.3, and 2.4
%    For more information, please see 
%    https://id3.org/Developer%20Information
%    
%    Syntax
%      tag = read_id3v2(file_name)
%
%    Input
%      file_name - (string) path to MP3 file
%
%    Output
%      tag - (struct) ID3 tag structure
%
%    the variable returns has 3 fields
%    HEADER is the header of the ID3 tag
%    FRAMES has a cell array of different frames
%    FRAMES_BREAKOUT is an attempt to make a structure
%    using different FRAME ID so that it would be easier to 
%    access the data
% 
%    Author:  San Nguyen (stn004@ucsd.edu)
%    Version: 1.0
%    Created: 2024-09-24
%

persistent ID3_str;
persistent ID3v2_TAG_HEADER_LENGTH;
persistent ID3v2_TAG_HEADER_TAG_SIZE_LENGTH;
persistent ID3v23_FRAME_HEADER_LENGTH;
persistent ID3v22_FRAME_HEADER_LENGTH;
persistent ID3v23_FRAME_HEADER_ID_LENGTH;
persistent ID3v23_FRAME_HEADER_SIZE_LENGTH;
persistent ID3v22_FRAME_HEADER_ID_LENGTH;
persistent ID3v22_FRAME_HEADER_SIZE_LENGTH;
persistent ID3v2_FRAME_HEADER_FLAGS_LENGTH;
persistent ID3v2_FRAME_ENCODING_LENGTH;
persistent ID3v2_COMMENT_FRAME_LANGUAGE_LENGTH;
persistent ID3v2_APIC_FRAME_PICTURE_TYPE_LENGTH;
persistent ID3v22_PIC_FRAME_IMAGE_FORMAT_LENGTH;

ID3_str = "ID3";
ID3v2_TAG_HEADER_LENGTH = 10;
ID3v2_TAG_HEADER_TAG_SIZE_LENGTH = 4;
ID3v23_FRAME_HEADER_LENGTH = 10;
ID3v22_FRAME_HEADER_LENGTH = 6;
ID3v22_FRAME_HEADER_ID_LENGTH = 3;
ID3v22_FRAME_HEADER_SIZE_LENGTH = 3;
ID3v23_FRAME_HEADER_ID_LENGTH = 4;
ID3v23_FRAME_HEADER_SIZE_LENGTH = 4;
ID3v2_FRAME_HEADER_FLAGS_LENGTH = 2;
ID3v2_FRAME_ENCODING_LENGTH = 1;
ID3v2_COMMENT_FRAME_LANGUAGE_LENGTH=3;
ID3v2_APIC_FRAME_PICTURE_TYPE_LENGTH = 1;
ID3v22_PIC_FRAME_IMAGE_FORMAT_LENGTH = 3;

tag = struct();
if ~exist(file_name,'file')
    error("read_id3v2:file_not_exist",'File does not exist.');
end

fid = fopen(file_name, "rb");
try
    if (fid ~= -1)
        tag_header_buffer = fread(fid, ID3v2_TAG_HEADER_LENGTH, '*char')';
    end
catch err
    
    
    if(fid)
        fid=fclose(fid);
    end
    error("read_id3v2:file_not_read",'There is an error reading file.');
    return
end
if(fid>2)
    fid = fclose(fid);
end
hdr_tag = read_id3v2_parse_header(tag_header_buffer);
if isempty(hdr_tag)
    tag = [];
    return
end
buffer_size = hdr_tag.tag_size+ID3v2_TAG_HEADER_LENGTH;
fid = fopen(file_name, "rb");

try
    if (fid ~= -1)
        buffer = fread(fid, buffer_size, '*char')';
    end
catch err
    if(fid)
        fid=fclose(fid);
    end
    error("read_id3v2:file_not_read",'There is an error reading file.');
    return
end
if(fid>2)
    fid = fclose(fid);
end
[hdr_tag,buff_rem] = read_id3v2_parse_header(buffer);
if(hdr_tag.extended_header_size ~= 0)
    buff_rem = buff_rem((hdr_tag.extended_header_size+1):end);
end
tag.header = hdr_tag;
tag.frames = {};
tag.frames_breakout = struct();
ith = 1;
while(numel(buff_rem)>0)
    % parse frames
    [f,buff_rem] = read_id3v2_parse_frame(buff_rem,hdr_tag.major_version);
    if(~isempty(f))
        tag.frames{ith} = f;
        if(isfield(tag.frames_breakout,deblank(strtrim(f.id))))
            tag.frames_breakout.(deblank(strtrim(f.id)))(end+1) = f;
        else
            tag.frames_breakout.(deblank(strtrim(f.id))) = f;
        end
        ith= ith+1;
    else
        break;
    end
    % keyboard;
end
%
    function txt = read_id3v2_convert_from_uint8_to_utf16(buffer)
        if(isempty(buffer))
            txt = [];
            return;
        end
        t_uni = char(uint16(buffer(2:2:end))*256 + uint16(buffer(1:2:end-1)));
        if ~(t_uni(1) == 65534 | t_uni(1) == 65279)
            txt = buffer;
        else
            txt = t_uni(t_uni<char(56320) & t_uni>char(31));
        end
        
    end
    function [frame_hdr,buff_rem,indx] = read_id3v2_parse_v23_frame_header(buffer,ver)
        ver = uint8(ver);

        if(numel(buffer)<ID3v22_FRAME_HEADER_LENGTH)
            frame_hdr = [];
            buff_rem = buffer;
            indx = 1;
            return;
        end
        if (ver>2)
            if(numel(buffer)<ID3v23_FRAME_HEADER_LENGTH)
                frame_hdr = [];
                buff_rem = buffer;
                indx = 1;
                return;
            end
        end
        indx = 1;
        switch (ver)
            case{2}
                frame_hdr.id = buffer(indx+(1:ID3v22_FRAME_HEADER_ID_LENGTH)-1);
                indx = indx+ID3v22_FRAME_HEADER_ID_LENGTH;
            case{3,4}
                frame_hdr.id = buffer(indx+(1:ID3v23_FRAME_HEADER_ID_LENGTH)-1);
                indx = indx+ID3v23_FRAME_HEADER_ID_LENGTH;
        end
        % If the id is 0000, that means we already reached the end and we're inside the padding
        if strncmp(frame_hdr.id,char(zeros(1,4)),4)
            indx = 0;
            frame_hdr = [];
            buff_rem = buffer;
            return;
        end
        switch(ver)
            case 4
            frame_hdr.size = ...
                read_id3v2_syncint_decode_str(...
                buffer(indx+(1:ID3v23_FRAME_HEADER_SIZE_LENGTH)-1));
            indx = indx + ID3v23_FRAME_HEADER_SIZE_LENGTH;
            case 3
            frame_hdr.size = read_id3v2_btoi(...
                buffer(indx+(1:ID3v23_FRAME_HEADER_SIZE_LENGTH)-1));
            indx = indx + ID3v23_FRAME_HEADER_SIZE_LENGTH;
            case 2
            frame_hdr.size = read_id3v2_btoi(...
                buffer(indx+(1:ID3v22_FRAME_HEADER_SIZE_LENGTH)-1));
            indx = indx + ID3v22_FRAME_HEADER_SIZE_LENGTH;
        end
        if(ver>2)
            frame_hdr.flags = buffer(indx+(1:ID3v2_FRAME_HEADER_FLAGS_LENGTH)-1);
            indx = indx +ID3v2_FRAME_HEADER_FLAGS_LENGTH;
        end
        
        buff_rem = buffer(indx:end);
    end
% parse picture tag
    function [frame,buff_rem,indx] = read_id3v2_parse_v23_apic_frame_rem(buff_rem,frame,ver)
        ver = uint8(ver);
        indx = 1;
        frame.text_encoding = uint8(buff_rem(indx));
        indx = indx+ID3v2_FRAME_ENCODING_LENGTH;

        switch (ver)
            case 2
                mine_type_str_ln = ID3v22_PIC_FRAME_IMAGE_FORMAT_LENGTH;
                frame.mine_type = buff_rem(indx+(1:mine_type_str_ln)-1);
            case {3,4}
                mine_type_str_ln = 0;
                for i = indx:numel(buff_rem)
                    if(buff_rem(i)==char(0))
                        break;
                    end
                    mine_type_str_ln = mine_type_str_ln +1;
                end
                if(mine_type_str_ln>0)
                    frame.mine_type = buff_rem(indx+(1:mine_type_str_ln)-1);
                else
                    frame.mine_type = '';
                end
                mine_type_str_ln = mine_type_str_ln+1;% skip nul termination for string
        end
        indx = indx + mine_type_str_ln;

        frame.picture_type = buff_rem(indx+(1:ID3v2_APIC_FRAME_PICTURE_TYPE_LENGTH)-1);
        indx = indx+ID3v2_APIC_FRAME_PICTURE_TYPE_LENGTH;

        if(frame.text_encoding == 0)
            descption_str_ln = 0;
            for i = indx:numel(buff_rem)
                if(buff_rem(i)==char(0))
                    break;
                end
                descption_str_ln = descption_str_ln +1;
            end
        else % unicode
            descption_str_ln = 0;
            for i = indx:2:numel(buff_rem)
                if(buff_rem(i)==char(0) && buff_rem(i+1)==char(0))
                    break;
                end
                descption_str_ln = descption_str_ln +2;
            end
        end
        if(descption_str_ln>0)
            frame.description = buff_rem(indx+(1:descption_str_ln)-1);
        else
            frame.description = '';
        end
        % skip nul termination for string unicode
        if(frame.text_encoding == 0)
            descption_str_ln = descption_str_ln+1;
        else
            descption_str_ln = descption_str_ln+2;
        end
        indx = indx + descption_str_ln; 

        if(frame.text_encoding == 1)
            frame.description = read_id3v2_convert_from_uint8_to_utf16(frame.description);
        end

        pic_size = double(frame.header.size) - ...
            ID3v2_FRAME_ENCODING_LENGTH - ...
            mine_type_str_ln - ...
            ID3v2_APIC_FRAME_PICTURE_TYPE_LENGTH - ...
            descption_str_ln;
        frame.pic_data = buff_rem(indx+(1:pic_size)-1);
        indx = indx + pic_size; % skip nul termination for string
        buff_rem = buff_rem(indx:end);

        %making the image plotable
        fid = fopen('tmp','w');
        try
            n = fwrite(fid,uint8(frame.pic_data),"uint8");
        catch err
            disp(err)
        end
        if(fid)
            fid = fclose(fid);
        end
        try
        index = find(frame.mine_type=='/',1);
        if(isempty(index))
            index = 0;
        end
        frame.imdata = imread('tmp',lower(frame.mine_type(index+1:end)));
        catch err
            disp(err)
        end
        delete('tmp');
    end
    function [frame,buff_rem,indx] = read_id3v2_parse_v23_comment_frame_rem(buff_rem,frame)
        indx = 1;
        frame.text_encoding = uint8(buff_rem(indx)); 
        indx = indx+ID3v2_FRAME_ENCODING_LENGTH;
        
        frame.lang = buff_rem(indx+(1:ID3v2_COMMENT_FRAME_LANGUAGE_LENGTH)-1);
        indx = indx + ID3v2_COMMENT_FRAME_LANGUAGE_LENGTH;
        
        if(frame.text_encoding == 0)
            short_descrip_str_ln = 0;
            for i = indx:numel(buff_rem)
                if(buff_rem(i)==char(0))
                    break;
                end
                short_descrip_str_ln = short_descrip_str_ln +1;
            end
        else % unicode
            short_descrip_str_ln = 0;
            for i = indx:2:numel(buff_rem)
                if(buff_rem(i)==char(0) && buff_rem(i+1)==char(0))
                    break;
                end
                short_descrip_str_ln = short_descrip_str_ln +2;
            end
        end
        if(short_descrip_str_ln>0)
            frame.short_desc = buff_rem(indx+(1:short_descrip_str_ln)-1);
        else
            frame.short_desc = '';
        end
        if(frame.text_encoding == 0)
            short_descrip_str_ln = short_descrip_str_ln+1;
            % skip nul termination for string
        else
            short_descrip_str_ln = short_descrip_str_ln+2;
            % skip nul termination for string unicode
        end
        indx = indx + short_descrip_str_ln;
        
        comment_ln = double(frame.header.size) - ...
            ID3v2_FRAME_ENCODING_LENGTH - ...
            ID3v2_COMMENT_FRAME_LANGUAGE_LENGTH - ...
            short_descrip_str_ln;
        if(comment_ln>0)
            frame.comment = buff_rem(indx+(1:comment_ln)-1);
        else
            frame.comment = '';
        end
        indx = indx + comment_ln;

        if(frame.text_encoding == 1)
            frame.short_desc = read_id3v2_convert_from_uint8_to_utf16(frame.short_desc);
            frame.comment = read_id3v2_convert_from_uint8_to_utf16(frame.comment);
        end
        buff_rem = buff_rem(indx:end);
    end
    function [frame,buff_rem,indx] = read_id3v2_parse_v23_txt_frame_rem(buff_rem,frame)
        indx = 1;
        frame.text_encoding = uint8(buff_rem(indx));
        indx = indx+ID3v2_FRAME_ENCODING_LENGTH;
        text_size = frame.header.size-ID3v2_FRAME_ENCODING_LENGTH;

        if(text_size>0)
            frame.text = buff_rem(indx+(1:text_size)-1);
        else
            frame.text = '';
        end
        if(frame.text_encoding == 1)
            frame.text = read_id3v2_convert_from_uint8_to_utf16(frame.text);
        end
        indx = indx + text_size;
        buff_rem = buff_rem(indx:end);
    end
    function [frame,buff_rem] = read_id3v2_parse_frame(buffer,ver)
        ver = uint8(ver);
        if(numel(buffer)<ID3v22_FRAME_HEADER_ID_LENGTH)
            frame = [];
            buff_rem = buffer;
            return;
        end
        if (ver>2 && (numel(buffer)<ID3v23_FRAME_HEADER_ID_LENGTH))
            frame = [];
            buff_rem = buffer;
            return;
        end
        [frame.header,buff_rem,indx] = read_id3v2_parse_v23_frame_header(buffer,ver);
        if(isempty(frame.header))
            frame = [];
            return;
        end
        frame.id = deblank(frame.header.id);
        if(isempty(frame.id))
            frame = [];
            return
        end
        switch(frame.id(1))
            case 'T' % text frame
                frame.type = 'text';
                [frame,buff_rem,indx] = read_id3v2_parse_v23_txt_frame_rem(buff_rem,frame);
            case 'C' % comment frame
                frame.type = 'comment';
                [frame,buff_rem,indx] = read_id3v2_parse_v23_comment_frame_rem(buff_rem,frame);
            case 'A' % APIC frame
                frame.type = 'pic';
                [frame,buff_rem,indx] = read_id3v2_parse_v23_apic_frame_rem(buff_rem,frame,ver);
            case 'P' % APIC frame
                if(ver==char(2) && strncmp(frame.id,"PIC",3))
                    frame.type = 'pic';
                    [frame,buff_rem,indx] = read_id3v2_parse_v23_apic_frame_rem(buff_rem,frame,ver);
                else
                    frame.type = 'other';
                    indx = 1;
                    frame.data = buff_rem(indx+(1:frame.header.size)-1);
                    indx = indx+frame.header.size;
                    buff_rem = buff_rem(indx:end);
                end
            otherwise
                frame.type = 'other';
                indx = 1;
                frame.data = buff_rem(indx+(1:frame.header.size)-1);
                indx = indx+frame.header.size;
                buff_rem = buff_rem(indx:end);
        end

    end
    function [tag,buff_rem] = read_id3v2_load_tag_with_buffer(buffer)
        
    end
    function [tag,buff_rem] = read_id3v2_parse_tag(buffer)

    end
    function [hdr_tag,buff_rem] = read_id3v2_parse_header(buffer)
        
        hdr_tag = [];
        if(strncmp(buffer,ID3_str,numel(ID3_str)))
            hdr_tag.tag = ID3_str;
            indx = 4;
            hdr_tag.major_version = buffer(indx);
            indx = indx +1;
            hdr_tag.minor_version = buffer(indx);
            indx = indx +1;
        end
        if(isempty(hdr_tag))
            return;
        end
        if (hdr_tag.major_version ~= char(2) && hdr_tag.major_version ~= char(3) && hdr_tag.major_version ~= char(4))
            hdr_tag = [];
            % No supported id3 tag found
            return;
        end
        if(isempty(hdr_tag))
            return;
        end
        hdr_tag.flags = buffer(indx);
        indx = indx +1;
        raw_size = buffer(indx+(0:(ID3v2_TAG_HEADER_TAG_SIZE_LENGTH-1)));
        indx = indx +4;
        hdr_tag.tag_size = read_id3v2_syncint_decode_str(raw_size);
        hdr_tag.extended_header_size = 0;
        if (numel(buffer)>ID3v2_TAG_HEADER_LENGTH)
            if (bitand(uint8(hdr_tag.flags),bitshift(1,6))>0)
                raw_size = buffer(indx+(0:(ID3v2_TAG_HEADER_TAG_SIZE_LENGTH-1)));
                indx = indx +4;
                hdr_tag.extended_header_size = read_id3v2_syncint_decode_str(raw_size);
            end
            hdr_tag.extended_header_size = 0;
        end
        
        buff_rem = buffer(indx:end);
    end % function read_id3v2_parse_header(buffer)
    function result = read_id3v2_btoi(char_buff)
        result = uint32(0);
        for i=1:numel(char_buff)
            result = bitshift(result,8);
            result = bitor(result,uint32(char_buff(i)));
        end
    end %function btoi(char_buff)
%
    function result=read_id3v2_syncint_decode(value)

        a = uint32(0);
        b = a;
        c = a;
        d = a;
        result = a;

        a = bitand(value,255);
        b = bitand(bitshift(value, -8), 0xFF);
        c = bitand(bitshift(value, -16), 0xFF);
        d = bitand(bitshift(value, -24), 0xFF);

        result = bitor(result,a);
        result = bitor(result,bitshift(b, 7));
        result = bitor(result,bitshift(c, 14));
        result = bitor(result,bitshift(d, 21));
    end %function result=syncint_decode(value)

    function result=read_id3v2_syncint_decode_str(char_buff)
        result = uint32(0);
        if(numel(char_buff)~=4)
            return;
        end
        result = bitor(result,uint32(char_buff(4)));
        result = bitor(result,bitshift(uint32(char_buff(3)), 7));
        result = bitor(result,bitshift(uint32(char_buff(2)), 14));
        result = bitor(result,bitshift(uint32(char_buff(1)), 21));
    end %function result=syncint_decode_str(char_buff)

end % function read_id3v2(file_name)