function st = kr_drhe_update(st, re, im)
%KR_DRHE_UPDATE  Cartesian-to-polar conversion of the ramp just coded and the
%   model update [3.5.3, Figure 3.16]: magnitude sqrt(re^2+im^2), phase
%   atan2(im, re), shifted into the history.
st.ph2 = st.ph;
st.ph  = atan2(im, re);
st.mag = sqrt(re.^2 + im.^2);
end
