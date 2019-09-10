%% SVM on cluster data
% EdA & SE updated 8/2019

% new analysis: pool all data. use 5-fold cross-val on "~540" data points held
% out, being the labels assigned to 20% medoids and their assoc clusters.
% make sure each fold equally samples within each of the six classes.
% train svm and render performance on held out.

close all
clear all

% basic stuff
sampmode = 'fixed'; % needs to be 'fixed' to use num_samp default or 'scaled' to use sampfactor
num_samp = 100; % default number of samples per cluster
sampfactor = 500; % downsample factor per cluster for 'scaled' mode
num_rev = 3; % number of expert reviewers assigning labels

location = 'C:\Users\Senan\Dropbox (Partners HealthCare)\@@@IRA_100cases\Features Clusters and Scores';
% location = uigetdir;
files = dir([location '\*.mat']);
% perc_agr = NaN(length(files),num_rev*2+1); % no longer for each patient

%pool all features from all patients into one file

%initialize full features, labels, and scores for all sampled data
afeats = [];
alabs = [];
ascores = []; % stored as [expert1 score, expert2 score, expert3 score]
medfeats = [];

%initialize cluster labels and ids
clustids = []; % stored as [patient, cluster index, datapoint index, cluster sample size, label]
med_nr = 1;

for n = setdiff(1:length(files),[17 50 87]) % leave out #17, #50 and #87 as they are missing iMedoid for at least 1cluster

    disp(strcat('processing patient # ',num2str(n)));
    load([location '\' files(n).name]) % load data
    samp_idx = [];
    
    
    % get 100 random samples of each cluster
    clusters = unique(IDX);
    for i=1:length(clusters)

        
        clust_idx = find(IDX==i & ~isOutlier);
        clust_idx = clust_idx(clust_idx~=iMedoids(i)); % remove medoid
        
                
        if(strcmp(sampmode,'fixed'))
        %  do nothing
        elseif(strcmp(sampmode,'scaled'))
            num_samp = ceil(length(clust_idx)/sampfactor);
            disp(num_samp)
        else
            print('mode not recognized');
        end
        
        if length(clust_idx)>num_samp
            samp_idx = [samp_idx;randsample(clust_idx,num_samp)];
            lc = num_samp;
        else % some clusters have less than 100 samples
            samp_idx = [samp_idx;clust_idx];
            lc = length(clust_idx);
        end
        
        scr = scores_mrg(iMedoids(i),:);
        [lb,freq] = mode(scr');
        lb(freq==1) = NaN;
        
        % stored as [patient, cluster index, datapoint index, cluster sample size, label]
        % label_1, label_2 and label_3 added
        idclust = [n,i,iMedoids(i),lc,lb,scr,med_nr];
        clustids = [clustids; idclust];
        
        alabs = [alabs,lb*ones(1,lc)]; % manually add label to all cluster samples
        ascores = [ascores;ones(lc,1)*scr];
       med_nr = med_nr+1; 
    end
    
    features = featureArray(samp_idx,:);
    afeats = [afeats;features];
    medfeatures = featureArray(iMedoids,:);
    medfeats = [medfeats;medfeatures];
    
%     [labels_maj,freq] = mode(scores_mrg(samp_idx,:)');
%     labels_maj(freq==1) = NaN; % if none agree, leave it out
%     
%     alabs = [alabs,labels_maj];
%     
%     ascores = [ascores;scores_mrg(samp_idx,:)];
    
end



%% PCA for 95% var retained

% PCA, retaining 95% of variance
[feat_stnd,mu,sigma] = zscore(afeats);
[coeff,pc,~,~,expl,~] = pca(feat_stnd);
per = 0; d = 0;
while per<95
    d = d+1;
    per = per+expl(d);
end
pc = pc(:,1:d);

%% Generate strat sampled k-folds for pooled data for crossval SVM
lb = alabs';

% c = cvpartition(lb,'KFold',5); %random partitioning of all datapoints with stratification

%partition by medoids' label (strat) b/c need to keep the cluster together in the
%partitions
% c = cvpartition(clustids(:,5),'KFold',5);
c = cvpartition(length(clustids),'Kfold',5); % not strat but including nans



%% Cycle thru all folds

perc_agr = NaN(c.NumTestSets,num_rev*2+1);

rang = 1;%logspace(-5,4,10);
nonsevens = zeros(length(rang),c.NumTestSets);
% for k = 1:length(rang)
%     fprintf('boxconst = %d\n', rang(k))
%     
k = 1;

for i = 1:c.NumTestSets
    fprintf('This cycle started at %s\n', datestr(now,'HH:MM:SS.FFF'))
    disp(i)
    tridx = c.training(i);
    teidx = c.test(i);
    
    trclust = clustids(tridx,:);
    teclust = clustids(teidx,:);
    
    dataind = 1;
    
    pctrain = [];
    pctest = [];
    lbtrain = [];
    lbtest = [];
    
    %asteidx = [];
    
    for j = 1:length(teidx)
        
        % lc = 0;
        lc = clustids(j,4);
        % disp(j)
        if teidx(j) == 1
            % if test then add to test
            % disp('yes')
%             pctest = [pctest; pc(dataind:dataind+lc-1,:)];
%             lbtest = [lbtest; lb(dataind:dataind+lc-1,:)];
%             asteidx = [asteidx; ones(lc,1)]; % exclude from test score index
%             tefeats = featureArray(clustids(j,3),:); % take only medoid 
            tefeats = medfeats(clustids(j,end),:);
            test_stnd = (tefeats-mu)./sigma; % standardize data
            pc_test = (test_stnd - repmat(mean(test_stnd),[size(test_stnd,1),1]))*coeff;
            pc_test = pc_test(:,1:d);
            pctest = [pctest;pc_test];
            lbtest = [lbtest;clustids(j,5)];

            %dataind stores correct index / debugged index error / no need
            %to standardize the data again -SE Sep 6, 2019
%             pctest = [pctest; pc(dataind,:)]; % Only add the PCs for the medoids
%             lbtest = [lbtest;lb(dataind)]; % Only add the label for the medoids
            
            
        elseif tridx(j) == 1
            % if train then add to train
            % disp('no')
            pctrain = [pctrain; pc(dataind:dataind+lc-1,:)];
            lbtrain = [lbtrain; lb(dataind:dataind+lc-1,:)];
            %asteidx = [asteidx; zeros(lc,1)];
%             if any(isnan(lbtrain))
%                 disp(dataind);
%                 return
%             end
        end
        
        dataind = dataind + lc; % still going to assign the entire cluster to sets even if only using medoids to train
            
    end
    
    % elim all nans -- unnecessary ||    pctest(~any(~isnan(pctest), 2),:)=[];
   
    % downsample 'Other' in training dataset if over 50% are 'Other'
    
%     lbtrainold = lbtrain;
%     pctrainold = pctrain;
%     lbtrain = [];
%     pctrain = [];
    
%     if sum(lbtrainold == 7)/length(lbtrainold) > 0.5
%         for m = 1:length(lbtrainold)
%             if lbtrainold(m) == 7
%                 if rand < 0.2
%                     lbtrain = [lbtrain; lbtrainold(m)];
%                     pctrain = [pctrain; pctrainold(m,:)];
%                 end
%             else
%                 lbtrain = [lbtrain; lbtrainold(m)];
%                 pctrain = [pctrain; pctrainold(m,:)];
%             end
%         end
%     end
%                     
                
    %t = templateSVM('KernelFunction','linear'); %,'BoxConstraint',rang(k)); % gaussian SVM
    NumTrees = 1000;
    %fitmdl = @(xtr,ytr)(fitcecoc(xtr,ytr,'Learners',t));%,'Prior','uniform'));
    fitmdl = @(xtr,ytr)(TreeBagger(NumTrees,xtr,ytr,'Method','classification','Prior','uniform'));
    
    disp('training model')
    Mdl = fitmdl(pctrain,lbtrain);
    disp('predicting')
    pred = predict(Mdl,pctest);
    pred = str2double(pred);
    
    disp('pred done')
    % calculate interrater agreements for each fold in following order:
    
    % 'Mv1','Mv2','Mv3','MvAll','1v2','1v3','2v3'
    
    %asteidx = (asteidx == 1);
    
%     perc_agr(i,1) = sum(pred==ascores(asteidx,1))...
%         /length(ascores(asteidx,1));
     perc_agr(i,1) = sum(pred==clustids(teidx,6))...
         /length(clustids(teidx,6));    

    % disp(perc_agr(i,1))
%     perc_agr(i,2) = sum(pred==ascores(asteidx,2))...
%         /length(ascores(asteidx,1));
    perc_agr(i,2) = sum(pred==clustids(teidx,7))...
        /length(clustids(teidx,6));
%     perc_agr(i,3) = sum(pred==ascores(asteidx,3))...
%         /length(ascores(asteidx,1));
    perc_agr(i,3) = sum(pred==clustids(teidx,8))...
        /length(clustids(teidx,6));
    
    perc_agr(i,4) = sum(pred==lbtest)... % NaNs still included, they should be removed
        /length(lbtest);
    
%     perc_agr(i,5) = sum(ascores(asteidx,1)==ascores(asteidx,2))...
%         /length(ascores(asteidx,1));
%     perc_agr(i,6) = sum(ascores(asteidx,1)==ascores(asteidx,3))...
%         /length(ascores(asteidx,1));
%     perc_agr(i,7) = sum(ascores(asteidx,2)==ascores(asteidx,3))...
%         /length(ascores(asteidx,1));
    perc_agr(i,5) = sum(clustids(teidx,6)==clustids(teidx,7))...
        /length(clustids(teidx,6));
    perc_agr(i,6) = sum(clustids(teidx,6)==clustids(teidx,8))...
        /length(clustids(teidx,6));
    perc_agr(i,7) = sum(clustids(teidx,7)==clustids(teidx,8))...
        /length(clustids(teidx,6));
    
    nonsevens(k,i) = sum(pred~=7);
    
    disp((sum(pred~=7)))
    fprintf('This cycle ended at %s\n', datestr(now,'HH:MM:SS.FFF'))
end

% plot results
figure;boxplot(perc_agr)
ylabel('percentage agreement');xticklabels({'Mv1','Mv2','Mv3','MvAll','1v2','1v3','2v3'});

% Stat tests

%2 samp t-test
machine = reshape(perc_agr(:,1:3),[1,15]);
human = reshape(perc_agr(:,5:7),[1,15]);
[h, p] = ttest2(human, machine)
%Emile - add any others here

% end

% %% Testing
% 
% c = cvpartition(clustids(:,5),'KFold',5);
% 
% perc_agr = nan(c.NumTestSets,7);
% 
% for i = 1:c.NumTestSets
%     fprintf('This cycle started at %s\n', datestr(now,'HH:MM:SS.FFF'))
%     disp(i)
%     tridx = c.training(i);
%     teidx = c.test(i); 
%     
%     asteidx = [];
%       
%     for j = 1:length(teidx)
%         lc = clustids(j,4);
%         % disp(j)
%         if teidx(j) == 1
%             % if training then add to training
%             % disp('yes')
%             asteidx = [asteidx; ones(lc,1)]; % exclude from test score index
%         else
%             % if test then add to test
% 
%             asteidx = [asteidx; zeros(lc,1)];
%         end
% 
%             
%     end
%     
%     % calculate interrater agreements for each fold in following order:
%  
%     asteidx = (asteidx == 1);
%     perc_agr(i,5) = sum(ascores(asteidx,1)==ascores(asteidx,2))...
%         /length(ascores(asteidx,1));
%     perc_agr(i,6) = sum(ascores(asteidx,1)==ascores(asteidx,3))...
%         /length(ascores(asteidx,1));
%     perc_agr(i,7) = sum(ascores(asteidx,2)==ascores(asteidx,3))...
%         /length(ascores(asteidx,1));
%     
%     fprintf('This cycle ended at %s\n', datestr(now,'HH:MM:SS.FFF'))
% end
% 
% % plot results
% figure;boxplot(perc_agr)
% ylabel('percentage agreement');xticklabels({'Mv1','Mv2','Mv3','MvAll','1v2','1v3','2v3'});
