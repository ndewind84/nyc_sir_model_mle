% between march 22 and april 4 the number of infected was about 15%
% the ifr is between 0.5% and 1%
% transmission rate follows the apple mobility curve
% recovery days = 15 (https://www.nature.com/articles/s41591-020-0869-5)

% fixed parameters
ndays = 180;
inter = 24;
nycpop = 8700000;

% load nyc doh data
[datatable] = load_nychealth_data;
datatable = datatable(1:end-7,:);
firstDay = datatable.date_of_death(1);
daysFromJan2020 = round(days(firstDay - datetime('1-Jan-2020')));
for kday = 1:daysFromJan2020
    datatable = [{firstDay-days(kday),0,0};datatable];
end
save('dohdata','datatable')
allDate = datatable.date_of_death;
% load('dohdata','datatable')

% apple movement data
appeDataFName = 'applemobilitytrends-2020-04-28.csv'; % must download and save manually
opts = detectImportOptions(appeDataFName);
opts.VariableNamesLine = 1; opts.DataLine = 2;
appleData = readtable(appeDataFName,opts);
nycindx = find(strcmp(appleData.Var2,'New York City'));
appleDates = ( datetime('Jan/13/2020'):...
    datetime('Jan/13/2020')+days(size(appleData,2)-4) )';
appleDates = [ (datetime('Jan/1/2020') + days(0:11))' ; appleDates];
appleMobile = mean(appleData{nycindx,4:end})'/100;
appleMobile = [ones(12,1);appleMobile];
appleMobileEndMean = mean(appleMobile(end-6:end));
appleMobileHourInterp = interp1(1:numel(appleMobile),appleMobile,1:1/inter:numel(appleMobile))';
padSize = inter*ndays - numel(appleMobileHourInterp);
if sign(padSize)
    appleMobileHourInterp = ...
        [appleMobileHourInterp;repmat(appleMobileEndMean,padSize+1,1)];
else
    appleMobileHourInterp = appleMobileHourInterp(1:end+padSize+1);
end

% set globals
% global recovDay
% global lingerDays
% global ifr

% fit model
options = optimset('Display','iter');
x0 = [0.0007, 0, sqrt(0.36), 0.008, sqrt(14), 1]
[x,fval,exitflag,output] = ...
    fminsearch(@sir_nyc_obj_wrapper_maxfree_apple_doh,x0,options)

% extract model parameters
i0 = x(1);
transRate = x(2)^2;
transRateAppleScalar = x(3)^2;
ifr = x(4);
recovDay = x(5)^2;
lingerDays = (sin(x(6))*0.5+0.5) * 21;

% report info
fprintf('\n\nFit Parameters\n')
fprintf('Number infected %s: %d\n',datestr(allDate(1)),round(i0*nycpop))
fprintf('R0 (pre lockdown): %0.3f\n',...
    (appleMobile(1) * transRateAppleScalar + transRate) * recovDay)
fprintf('R0 (post lockdown): %0.3f\n',...
    (appleMobile(end) * transRateAppleScalar + transRate) * recovDay)
fprintf('IFR: %0.2f%%\n',ifr*100)
fprintf('Recovery time (days): %0.1f \n',recovDay)
fprintf('Death delay (days): %0.1f\n',lingerDays)

% extract NYC cummulative death data
thisCumDeath = cumsum(datatable.CONFIRMED_DEATHS+datatable.PROBABLE_DEATHS)...
    / nycpop;
thisDailyDeath = (datatable.CONFIRMED_DEATHS+datatable.PROBABLE_DEATHS)...
    / nycpop;
% firstDeathIndx = find(thisDailyDeath>0,1,'first');
allDate = datatable.DATE_OF_INTEREST;

% lockdown date for NYC
realLockDownDay = datetime('3/22/2020','InputFormat','MM/dd/yyyy');
lockdownDay = find(allDate == realLockDownDay)-1;

% calculate parameter predictions
[s,i,r,d,t] = calculate_SIRD_mobility(...
    i0,ifr,appleMobileHourInterp * transRateAppleScalar + transRate,...
    recovDay,ndays,inter);

% lockdown date for NYC
realLockDownDay = datetime('3/22/2020','InputFormat','MM/dd/yyyy');
lockdownDay = find(allDate == realLockDownDay)-1;

% add death delay
d = [zeros(1,round(lingerDays*inter)),d(1:end-round(lingerDays*inter))];

% create hourly time axis with real date
realT = allDate(1) + t;

% pregnancy study time index
studyTindx = realT > datetime('3/22/2020','InputFormat','MM/dd/yyyy') & ...
    realT < datetime('4/4/2020','InputFormat','MM/dd/yyyy');

% antibody study time index
studyTindx2 = realT > datetime('4/20/2020','InputFormat','MM/dd/yyyy') & ...
    realT < datetime('4/22/2020','InputFormat','MM/dd/yyyy');

% figures
figure(1)
plot(realT,[s;i;r;d]'.*nycpop./(10^6),'linewidth',2);
hold on;
plot(realT(studyTindx),repmat(0.15,1,sum(studyTindx)).*nycpop./(10^6),'-',...
    'color',[1,.65,.65],'linewidth',2)
plot(realT(studyTindx2),repmat(0.21,1,sum(studyTindx2)).*nycpop./(10^6),'-',...
    'color',[1,.65,.0],'linewidth',2)
plot([realLockDownDay,realLockDownDay],[0,1].*nycpop./(10^6),...
    '--k','linewidth',1.5)
hold off;
legend('location','southoutside',...
    {'Susceptible','Infected','Recovered','Dead','Est. Infect.',...
    'Est. Recov','Lockdown'})
ylabel('Millions of people')
ax=gca;grid on;
set(ax,'box','off')
set(ax,'XLim',[realT(1),realT(end)])
set(ax,'YLim',[0,1].*nycpop./(10^6))


figure(2)
plot(realT,[s;i;r;d]'.*nycpop./(10^3),'linewidth',2);
hold on;
plot(allDate,thisCumDeath.*nycpop./(10^3),'linewidth',2);
plot([realLockDownDay,realLockDownDay],[0,1].*nycpop./(10^3),...
    '--k','linewidth',1.5)
hold off;
legend('location','southoutside',...
    {'Susceptible','Infected','Recovered','Dead','NYC real deaths','Lockdown'})
ylabel('Thousands of people')
ax = gca;grid on;
set(ax,'box','off')
set(ax,'XLim',[realT(1),allDate(end)+range(allDate)/10])
set(ax,'YLim',[0,max(thisCumDeath)+max(thisCumDeath)/10].*nycpop./(10^3))

figure(3)
plot(realT,[s;i;r;d]'.*nycpop./(10^3),'linewidth',2);
hold on;
plot(allDate,thisCumDeath.*nycpop./(10^3),'linewidth',2);
plot([realLockDownDay,realLockDownDay],[0,1].*nycpop./(10^3),...
    '--k','linewidth',1.5)
hold off;
legend('location','southoutside',...
    {'Susceptible','Infected','Recovered','Dead','NYC real deaths','Lockdown'})
ylabel('Thousands of people')
ax = gca;grid on;
set(ax,'box','off')
set(ax,'XLim',[realT(1),realT(end)])
set(ax,'YLim',[0,max(d)+max(d)/10].*nycpop./(10^3))

figure(4)
% build log y-axis with interpretable intervals and labels
yticks = [1,2,5];
for kom = 1:9
    yticks = [yticks,[1,2,5]*10^kom];
end
clear yticklabelarray
for ky = 1:numel(yticks)
    yticklabelarray{ky} = sprintf('%d',yticks(ky));
end
predDD = diff(d(1:inter:end))*nycpop;
dd = diff(thisCumDeath)*nycpop;
plot(allDate(2:end),log10(dd),'linewidth',2); hold on;
plot(log10(predDD),'linewidth',2); hold off;
set(gca,'ytick',log10(yticks),'yticklabel',yticklabelarray)
legend('location','southoutside',...
    {'NYC deaths(adjusted for home deaths)','Model predicted deaths'})
ylabel('Deaths per day')
ax = gca;grid on;
set(ax,'box','off')
set(ax,'XLim',[realT(1),realT(end)])
set(ax,'YLim',[0,max(log10(dd))+max(log10(dd))/10])

figure(5)
plot(realT,(appleMobileHourInterp * transRateAppleScalar + transRate).*s'.*recovDay,...
    '-k','linewidth',2)
hold on;
plot([realT(1),realT(end)],[1,1],'--k','linewidth',2)
hold off;
set(gca,'XLim',get(ax,'XLim'))
