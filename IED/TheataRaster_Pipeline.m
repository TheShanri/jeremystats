function TheataRaster_Pipeline();
% a template to analysis on csd analysis output



%TO get data out of SpikeSelector CSD output

fig = gcf;

dataObjs = findobj(fig,'-property','XData');
 x1 = dataObjs(1).XData;
dataObjs = findobj(fig,'-property','YData');
y1 = dataObjs(1).YData;
dataObjs = findobj(fig,'-property','CData');
c1 = dataObjs(1).CData;



c2=c1;
Positive = c2 > 0;
c2(~Positive) = 0;
MeanPositive = sum(c2, 2) ./ sum(Positive, 2);

 figure
      imagesc(x1,y1,c2)
      colorbar
      colormap (jet)
      
c3=c1;
Negative = c3 < 0;
c3(~Negative) = 0;
MeanNegative = sum(c3, 2) ./ sum(Negative, 2);

 figure
      imagesc(x1,y1,c3)
      colorbar
      colormap (jet)


figure
plot(MeanPositive,y1,'k')
set(gca,'ydir','rev')
ylim([0 35])


figure
plot(MeanNegative,y1,'k')
set(gca,'ydir','rev')
ylim([0 35])

%%
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s3_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s3_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s3_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s3_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s3_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s8_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s8_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s8_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s8_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M2_s8_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s4_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s4_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s4_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s4_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s4_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s8_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s8_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s8_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s8_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M6_s8_CNO\MeanPositive.mat', 'MeanPositive')


save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s3_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s3_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s3_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s3_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s3_baseline\MeanPositive.mat', 'MeanPositive')


save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s8_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s8_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s8_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s8_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\CTL\M15_s8_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s8_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s8_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s8_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s8_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M1_s8_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s7_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s7_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s7_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s7_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M3_s7_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s7_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s7_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s7_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s7_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M5_s7_CNO\MeanPositive.mat', 'MeanPositive')


save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s2_baseline\MeanPositive.mat', 'MeanPositive')


save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s6_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s6_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s6_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s6_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M7_s6_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s9_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s9_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s9_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s9_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M8_s9_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s4_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s4_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s4_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s4_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s4_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s7_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s7_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s7_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s7_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M10_s7_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s10_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s10_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s10_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s10_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s10_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s11_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s11_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s11_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s11_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M11_s11_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s2_baseline\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s2_baseline\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s2_baseline\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s2_baseline\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s2_baseline\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\MeanPositive.mat', 'MeanPositive')

save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s1_baseline_shallower\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s1_baseline_shallower\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s1_baseline_shallower\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s1_baseline_shallower\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s1_baseline_shallower\MeanPositive.mat', 'MeanPositive')


save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\x1.mat', 'x1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\c1.mat', 'c1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\y1.mat', 'y1')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\MeanNegative.mat', 'MeanNegative')
save('C:\Users\Z390\Desktop\PTEN_CSDsEtc\PTEN\M13_s17_CNO\MeanPositive.mat', 'MeanPositive')

%%
%

% go to path 
% 
% open .mat files
% 
% then average + and - current by depth
% 
% make line plots
% 
% need to average this across animals
% 
%       figure
%       imagesc(x1,y1,c1)
%       colorbar
%       colormap (jet)
%       axis xy
% 
      
            for BB=1:length(c1)
                if BB < 0 
                   BB == 0
                end;
            end;  
                
      
      for c1 1:end
      if c1 < 0
          c1 == 0;
          
      end
      
      
      
      ccc=mean(c1);
      think of y1 (depth) as frequency in spectrogram analysis 
      could specify the averages for depth ranges
       figure
plot(x1, ccc,'k')

That's collapsing all sinks and sources over the 8 secs, which is kind of interesting

ccc=mean(c1,2); %This collapses mean across rows
figure
plot(y1, ccc,'k')
%This is actually pretty cool, but not what I first envisioned
says which layers are more a source than sink



% %This is one way to go about it but it doesn't work : /
% [m,n] = size(A);
% MeanP(1:n) = 0;
% for j = 1:n
%     npos = 0;
%     for i = 1:m
%         if A(i,j) > 0
%             npos = npos+1;
%             MeanP(j) = MeanP(j) + A(i,j);
%         end
%     end
%     if npos > 0
%         MeanP(j) = MeanP(j)/npos;
%     end
% end
% 

Is there a difference in the degree of synaptic excitation or inhibiiton per group?

c2=c1;
Positive = c2 > 0;
c2(~Positive) = 0;
MeanPositive = sum(c2, 2) ./ sum(Positive, 2);



 figure
      imagesc(x1,y1,c2)
      colorbar
      colormap (jet)
      
      
      

c3=c1;
Negative = c3 < 0;
c3(~Negative) = 0;
MeanNegative = sum(c3, 2) ./ sum(Negative, 2);

 figure
      imagesc(x1,y1,c3)
      colorbar
      colormap (jet)


figure
plot(MeanPositive,y1,'k')
set(gca,'ydir','rev')
ylim([0 35])


figure
plot(MeanNegative,y1,'k')
set(gca,'ydir','rev')
ylim([0 35])

