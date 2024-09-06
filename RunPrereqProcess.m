%{
Invokes PrereqProcess class to construct a matrix representing the
prerequisites of all courses.
%}

% Import data
clc, clear
data = readtable("Caam378 MP3 - Couse Data 2020-2021 - Final.xlsx", 'Sheet', "Summary");
titles = string(data.Title);
prereqs = string(data.Prerequisites);
coreqs = string(data.Corequisites);

%{
Instantiate PrereqProcess object and use to build prerequisite matrix.
mat is a square matrix of size equal to the number of courses (including
auxiliary courses built by PrereqProcess). Element i,j  has meaning:
0: course i does not prereq course j
1: course i strict-and prereqs course j
2: course i strict-or prereqs course j
3: course i concurrent-and prereqs course j
4: course i concurrent-or prereqs course j
%}
prereq = PrereqProcess(titles, prereqs, coreqs);
prereq.buildPrereqMatrix()
mat = prereq.getPrereqMatrix();
prereq.writePrereqMatrixXlsx("Prerequisite Matrix 3.xlsx");