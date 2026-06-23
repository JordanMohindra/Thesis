function printKiemReference()
% PRINTKIEMREFERENCE Prints Kiem's Table 3.5 reference numbers (real data).
    fprintf('\n  --- Kiem Reference (Table 3.5, real data) ---\n');
    fprintf('  %-10s %6s %8s %8s %14s %10s\n', 'Algorithm', 'CR', 'FN (%)', 'FP (%)', 'NF est.(dBFS)', 'SNR (dB)');
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', 'FP16*', 1.00, 0.00, 0.00, -70.714, 22.407);
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', 'FX16*', 1.00, 0.59, 1.18, -70.691, 22.330);
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', 'DRHE*', 3.25, 0.59, 1.18, -70.691, 22.330);
end
