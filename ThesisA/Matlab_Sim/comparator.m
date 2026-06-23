function [falsePositives, falseNegatives] = comparator(detectionListRef, detectionListTest)
% COMPARATOR Compares detection lists from reference and test paths.
%   As described in Section 3.2.1 and 3.4.2 of Kiem's thesis.
%
%   Input:
%     detectionListRef  - logical mask from reference path (FP16)
%     detectionListTest - logical mask from algorithm under test
%
%   Output:
%     falsePositives - count of detections in test but NOT in reference
%     falseNegatives - count of detections in reference but NOT in test

    falsePositives = sum(detectionListTest(:) & ~detectionListRef(:));
    falseNegatives = sum(detectionListRef(:) & ~detectionListTest(:));
end
