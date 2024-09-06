%% Introduction
%{
Runs the MIP model to create a four-year plan schedule (or a schedule of
arbitrary semester length).
First imports relevant data; then solves MIP using SchedulingModel2 class.
%}
clc, clear

%% Import data
%{
Imports courseTbl of course logistical/stress data and prereqTbl of course
prerequisite data.
%}
courseTbl = readtable("Caam378 MP3 - Couse Data 2020-2021 - Final.xlsx", 'Sheet', "Summary");
prereqTbl = readtable("Prerequisite Matrix 3.xlsx");
sAndFlag = 1;
sOrFlag = 2;
cAndFlag = 3;
cOrFlag = 4;
Stress = courseTbl.Workload .* courseTbl.Grade;
courseTbl = horzcat(courseTbl, table(Stress));
defaultStress = 3.625;

%% Construct schedule
%{
User specifies schedule parameters (numSems, stressMultiplier,
nextSemFall). User also specified required courses to take before 
graduation and existing courses they have already taken.
MIP solves for schedule based on these parameters.
%}
% Semester parameters
clc
numSems = 5;
semStressMultiplier = ones(numSems, 1);
%semStressMultiplier(1) = 1.25;
%semStressMultiplier(numSems - 1 : numSems) = 1.1;
isNextSemFall = false;

% Required and existing course credits
filename = "Michael O Schedule.xlsx"
requiredTitles = string(table2array(readtable(filename, 'Sheet', "Required")))
existingTitles = string(table2array(readtable(filename, 'Sheet', "Existing")))

% Create MIP model and solve
mdl = SchedulingModel2(courseTbl, prereqTbl, sAndFlag, sOrFlag, cAndFlag, cOrFlag, defaultStress, semStressMultiplier, numSems, isNextSemFall, requiredTitles, existingTitles)
mdl.buildConstraints()
[sol, val] = mdl.solve(10 ^ 5)
schedule = mdl.solution2table(sol, false)
writetable(splitvars(schedule), filename, 'Sheet', "Schedule")
