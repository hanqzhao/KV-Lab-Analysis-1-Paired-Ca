% Aligning the baselines
function combined_data = subsweepAnalysis(data, par)
    % Get info from paradigm
    subsweeps = par{:, 1};
    numsweeps = size(subsweeps, 1);
    
    % Validate input length
    expected_length = sum(subsweeps);
    if length(data) ~= expected_length
        error('Trace length does not match expected length of %d', expected_length);
    end
    
    % Initialize combined_data array
    combined_data = zeros(expected_length, 1);
    
    % Adjust subsweeps
    data_idx = 1;
    for i = 1:numsweeps
        subsweep_length = subsweeps(i);
        
        current_subsweep = data(data_idx:data_idx+subsweep_length-1);
        
        % baseline removal using SNIP
        current_baseline = A1_funs.snip(current_subsweep, 20, true, 3);
        adjusted_subsweep = current_subsweep - current_baseline;
        
        combined_data(data_idx:data_idx+subsweep_length-1) = adjusted_subsweep;
        
        data_idx = data_idx + subsweep_length;
    end
end
