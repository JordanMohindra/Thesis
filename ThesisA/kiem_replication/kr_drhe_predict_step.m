function [pre, pim, st] = kr_drhe_predict_step(st, alpha, beta)
%KR_DRHE_PREDICT_STEP  One ramp of Kiem's DRHE model prediction [2.7.3, 3.5.3].
%   State (per range bin and channel), all from previous ramps:
%     st.magPred   a_hat[m-1]        st.mag   a[m-1]
%     st.phPred    theta_hat[m-1]    st.ph    theta[m-1]    st.ph2 theta[m-2]
%   Magnitude:  a_hat[m]     = alpha*a_hat[m-1] + (1-alpha)*a[m-1]        (3.5)
%   Phase:      theta_hat[m] = beta*theta_hat[m-1] + (2-beta)*theta[m-1]
%                              - theta[m-2]                               (3.6)
%               wrapped once into [-pi, pi] as in his HLS code
%   Cartesian prediction X_hat = a_hat * exp(j*theta_hat), rounded to integer
%   (the difference "is in the 16-bit integer format").
magPred = alpha * st.magPred + (1 - alpha) * st.mag;
phPred  = beta * st.phPred + (2 - beta) * st.ph - st.ph2;
phPred(phPred >  pi) = phPred(phPred >  pi) - 2*pi;
phPred(phPred < -pi) = phPred(phPred < -pi) + 2*pi;
pre = round(magPred .* cos(phPred));
pim = round(magPred .* sin(phPred));
st.magPred = magPred;
st.phPred  = phPred;
end
