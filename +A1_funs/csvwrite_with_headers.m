% Helper function to write CSV with headers (since MATLAB's csvwrite doesn't support headers)
function csvwrite_with_headers(filename, data, headers)
    % Open file
    fid = fopen(filename, 'w');
    
    % Write headers
    fprintf(fid, '%s,', headers{1:end-1});
    fprintf(fid, '%s\n', headers{end});
    
    % Close file
    fclose(fid);
    
    % Append numeric data
    dlmwrite(filename, data, '-append');
end

