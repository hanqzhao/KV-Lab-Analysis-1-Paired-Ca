% This scaling function takes into account the 0 values caused by filtering.
function scaled = scale16(imageStack)
    % Find non-zero pixels
    nonZeroMask = imageStack ~= 0;
    
    % Scale non-zero pixels to full 16-bit range, with minimum set to 0
    nonZeroMin = min(imageStack(nonZeroMask), [], 'all');
    imageStack(nonZeroMask) = (imageStack(nonZeroMask) - nonZeroMin) .* ...
        (65535 ./ (max(imageStack(nonZeroMask), [], 'all') - nonZeroMin));

    % Set zero pixels back to zero
    imageStack(~nonZeroMask) = 0;
    
    % Output the scaled image stack
    scaled = imageStack;
end
