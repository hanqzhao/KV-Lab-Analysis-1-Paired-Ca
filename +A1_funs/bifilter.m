function smoothed = bifilter(signal, order)
    % Ensure signal is a column vector
    signal = signal(:);
    
    % Padding strategy using reflection
    pad_left = signal(order+1:-1:2);
    pad_right = signal(end-1:-1:end-order);
    
    padded_signal = [pad_left; signal; pad_right];
    
    % Apply filter
    for i = 1:order
        padded_signal = conv(padded_signal, [1 2 1]/4, 'same');
    end
    
    % Remove padding and return to original shape
    smoothed = padded_signal(order+1:end-order);
end
