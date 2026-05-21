function baseline = snip(data, max_half_window, decreasing, smooth_half_window)
%SNIP Baseline correction using SNIP algorithm
%   data: Input signal
%   max_half_window: Maximum half-width of the clipping window
%   decreasing: Boolean, whether to process windows in decreasing order
%   smooth_half_window: Half-width of smoothing window (0 for no smoothing)

    % if ~ismember(filter_order, [2 4 6 8])
    %     error('filter_order must be 2, 4, 6, or 8');
    % end
    
    if decreasing
        rangeVec = max_half_window:-1:1;   % e.g. 40→39→…→1
    else
        rangeVec = 1:max_half_window;      % 1→2→…→40
    end

    % Pad the data to handle edge effects
    y = padarray(data(:), [max_half_window 0], 'replicate', 'both');
    baseline = y;
    
    if smooth_half_window > 0
        smooth_window = 2 * smooth_half_window + 1;
    end

    for i = rangeVec
        % Calculate the moving average filter
        vec1 = baseline(1:end-2*i);
        vec2 = baseline(1+2*i:end);
        filters = (vec1 + vec2) / 2;
        
        % Get the current region of interest
        ind = (1+i):(length(baseline)-i);
        current_region = baseline(ind);
        
        % Apply smoothing if requested
        if smooth_half_window > 0
            smoothed = movmean(current_region, smooth_window);
        else
            smoothed = current_region;
        end
        
        % Create mask for points above the filter
        mask = current_region > filters;
        
        % Update baseline
        baseline(ind) = smoothed;
        baseline(ind(mask)) = filters(mask);
    end
    
    % Remove padding
    baseline = baseline(max_half_window+1:end-max_half_window);
end
