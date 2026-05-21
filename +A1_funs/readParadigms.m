% Read the paradigms folder
function [tables, indices] = readParadigms(folderPath)
    % Get a list of all files in the folder
    files = dir(fullfile(folderPath, 'Par*.xlsx'));
    
    % Initialize cell arrays to store the tables and indices
    tables = cell(length(files), 1);
    indices = zeros(length(files), 1);
    
    % Loop through each file and read the tables
    for i = 1:length(files)
        fileName = fullfile(folderPath, files(i).name);
        
        % Extract the index from the file name
        [~, name, ~] = fileparts(files(i).name);
        index = str2double(name(4:end));
        
        % Read the table and store it with the index
        tables{i} = readtable(fileName, 'VariableNamingRule', 'preserve');
        indices(i) = index;
    end
end
