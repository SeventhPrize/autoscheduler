classdef SchedulingModel2 < handle
    %{
    Builds the MIP program used to create a four-year schedule.
    Using an input prerequisite matrix (see PrereqProcess), creates the
    constraints, objectives, decision variables needed for the MIP.
    %}
    properties
        courseTbl
        %{
        Table of data for courses. Has variables:
        Title; string titles of each course
        Fall; number of fall-semester course sessions (>0 if offered in
        fall)
        Spring; number of spring-semester course sessions (>0 if offered in
        spring)
        Stress; nonnegative double proportional to the stress induced by
        the course
        %}

        prereqTbl
        %{
        Table describing the prerequisites for each of n courses. Has variables:
        Title (column 1); string titles of each course
        Foreach column i = 2 : n; VariableName is the title of the ith
        course. Entry (i, j+1) is an integer flag for whether course i is
        a prerequisite for course j.
            Uses sAndFlag, sOrFlag, cAndFlag, cOrFlag to signal
            prerequisite type
        %}

        sAndFlag            % flag in prereqTbl for strict-and prereq
        sOrFlag             % flag in prereqTbl for strict-or prereq
        cAndFlag            % flag in prereqTbl for concurrent-and prereq
        cOrFlag             % flag in prereqTbl for concurrent-or prereq
        defaultStress       % default value for stress (there exist classes without stress data from Esther evals)
        semStressMultiplier % numerical array of length numSems. Element i is multiplied onto the total stress of semester i. (Some semesters, like the first semester of college, can be more stressful)

        numSems             % number of semesters
        isNextSemFall       % boolean whether the next semester is a fall semester (false = spring sem)
        fallSems            % array of integers representing the fall semester numbers
        springSems          % array of integers representing the spring semester numbers

        smallPrereqTbl      % same as obj.prereqTbl, except only stores data relevant to courses in obj.relevantInds. For computation load reduction.
        prereqMat           % array form of numerical data in smallPrereqTbl (table2array(smallPrereqTbl(2:end, :))

        required            % list of required course titles specified by user
        existing            % list of course titles already completed by user
        relevantInds        % list of indices of courses in required and all their prerequisites not already satisfied by obj.existing courses

        numCourses          % number of courses in relevantInds (length)
        numVars             % number of decision variables (one for each course * semester; one additional for auxiliary objective)

        ineqC               % inequality constraint coefficients
        ineqB               % inequality constraint bounds
        eqC                 % equality constraint coefficients
        eqB                 % equality constraint bounds
        lb                  % decision variable lower bounds
        ub                  % decision variable upper bounds
    end
    methods
        function obj = SchedulingModel2(courseTbl, prereqTbl, sAndFlag, sOrFlag, cAndFlag, cOrFlag, defaultStress, semStressMultiplier, numSems, isNextSemFall, required, existing)
            %{
            Constructor
            IN (see properties)
                courseTbl; table containing course availability/stress data
                prereqTbl; table containing matrix reprersenting prereq info
                sAndFlag, ..., cOrFlag; integer flags in prereqTbl
                representing prerequisite type
                defaultStress; double representing the default stress value
                of courses that do not have stress values in courseTbl data
                semStressMultiplier; numerical list; element i multiplies
                the stress of semester i
                numSems; number of semesters
                isNextSemFall; boolean whether next semester is fall
                semester
                required; list of strings of the course titles desired to
                be completed
                existing; list of strings of the course titles already
                completed
            %}
            % Initialize properties
            obj.courseTbl = courseTbl;
            obj.prereqTbl = prereqTbl;
            obj.sAndFlag = sAndFlag;
            obj.sOrFlag = sOrFlag;
            obj.cAndFlag = cAndFlag;
            obj.cOrFlag = cOrFlag;
            obj.defaultStress = defaultStress;
            obj.semStressMultiplier = semStressMultiplier;
            obj.numSems = numSems;
            obj.required = required;
            obj.existing = existing;

            obj.isNextSemFall = isNextSemFall;
            if isNextSemFall
                obj.fallSems = 1 : 2 : numSems;
                obj.springSems = 2 : 2 : numSems;
            else
                obj.fallSems =  2 : 2 : numSems;
                obj.springSems = 1 : 2 : numSems;
            end

            % Evaluating every course is too computationally intensive. Use
            % breadth-first-search to identify the list of relevant courses
            % (required courses + their prereqs/coreqs - existing courses)
            requiredInds = find(ismember(prereqTbl.Title, required));
            existingInds = find(ismember(prereqTbl.Title, existing));
            obj.relevantInds = obj.bfsRelevantCourses(obj.getPrereqMatFromTable(prereqTbl), requiredInds, existingInds);

            % Isolate the courses identified in obj.relevantInds. Reduces
            % computation load
            obj.smallPrereqTbl = prereqTbl(obj.relevantInds, [1; obj.relevantInds + 1]);
            obj.prereqMat = obj.getPrereqMatFromTable(obj.smallPrereqTbl);

            % Count the number of decision variables
            obj.numCourses = length(obj.relevantInds);
            obj.numVars = obj.numCourses * numSems + 1;
        end
        function ind = title2ind(obj, title, courseTbl)
            %{
            Finds the index at which the specified course title is stored
            in the Title variable of courseTbl
            %}
            ind = find(string(courseTbl.Title) == title);
            if length(ind) ~= 1
                ind = -1;
            end
        end
        function title = ind2title(obj, ind, courseTbl)
            %{
            Finds the title of the course stored in index in in
            courseTbl.Title
            %}
            title = courseTbl.Title(ind);
        end
        function [stress, dataExists] = getStress(obj, cIndSmallTbl)
            %{
            Finds the numerical stress of the course whose title is located
            at index cIndSmallTbl in obj.smallPrereqTbl.Title
            IN
                index of course's title in obj.smallPrereqTbl.Title
            OUT
                stress; numerical stress value (defaulted to
                obj.defaultStress)
                dataExists; boolean whether the data was available
            %}
            courseTitle = obj.ind2title(cIndSmallTbl, obj.smallPrereqTbl); % get course title
            % if the course is an auxiliary course, it has zero stress
            if extractBetween(courseTitle, 1, 4) == "AUXL"
                stress = 0;
                dataExists = true;
                return;
            end
            % find stress value
            cIndInfoTbl = obj.title2ind(courseTitle, obj.courseTbl); % find course row index in obj.courseTbl
            stress = obj.courseTbl.Stress(cIndInfoTbl);
            dataExists = true;
            if isnan(stress)
                stress = obj.defaultStress;
                dataExists = false;
            end
        end
        function [isFall, isSpring, dataExists] = getSeasonal(obj, cIndSmallTbl)
            %{
            Finds the fall/spring availabililty of the course whose title is located
            at index cIndSmallTbl in obj.smallPrereqTbl.Title
            IN
                index of course's title in obj.smallPrereqTbl.Title
            OUT
                isFall; boolean course availability in fall
                isSpring; boolean course availability in spring
                dataExists; boolean whether the data was available
            %}
            courseTitle = obj.ind2title(cIndSmallTbl, obj.smallPrereqTbl); % get course title
            % if course is an auxiliary course, it is always available
            if extractBetween(courseTitle, 1, 4) == "AUXL"
                isFall = true;
                isSpring = true;
                dataExists = true;
                return;
            end
            % find course availability
            cIndInfoTbl = obj.title2ind(courseTitle, obj.courseTbl); % find course row index in obj.courseTbl
            isFall = (obj.courseTbl.Fall(cIndInfoTbl) > 0);
            isSpring = (obj.courseTbl.Spring(cIndInfoTbl) > 0);
            dataExists = true;
            if isnan(isFall)
                isFall = false;
                isSpring = false;
                dataExists = false;
            end
        end
        function [hours, dataExists] = getHours(obj, cIndSmallTbl)
            %{
            Finds the credit hour count of the course whose title is located
            at index cIndSmallTbl in obj.smallPrereqTbl.Title
            IN
                index of course's title in obj.smallPrereqTbl.Title
            OUT
                hours; integer number of credit hours of the course
                dataExists; boolean whether the data was available
            %}
            courseTitle = obj.ind2title(cIndSmallTbl, obj.smallPrereqTbl); % get course title
            % If the course is an auxiliary course, it is zero credit hours
            if extractBetween(courseTitle, 1, 4) == "AUXL"
                hours = 0;
                dataExists = true;
                return;
            end
            % find credit hour info from obj.courseTbl
            cIndInfoTbl = obj.title2ind(courseTitle, obj.courseTbl); % get row index of course in obj.courseTbl
            hours = obj.courseTbl.Hours(cIndInfoTbl);
            dataExists = true;
            if isnan(hours)
                dataExists = false;
            end
        end
        function relevantInds = bfsRelevantCourses(obj, prereqMat, required, existing)
            %{
            Uses breadth-first-search to find all prerequisites of the
            courses in required, then returns a list of the obj.courseTbl-indices
            of all courses in required and its prerequistes that aren't
            already satisfied by existing coursework
            IN
                prereqMat, matrix describing the prerequisites of all
                courses (elm i,j > 0 implies course i prereqs course j)
                required; prereqMat-indices of required courses
                existing; prereqMat-indices of courses that have already
                been completed
            OUT
                relevantInds; list of prereqMat-indices of courses that are
                required or prereqs of required courses that aren't
                satisfied by existing course credits
            %}
            queue = setdiff(required, existing); % queue all required courses that haven't already been completed
            relevant = zeros(height(prereqMat), 1); % boolean array, where the element i represents whether course i in prereqMat is relevant
            relevant(queue) = 1;
            % Run BFS to accumulate which courses are relevant
            while ~isempty(queue)
                node = queue(1);
                queue(1) = [];
                for child = 1 : height(prereqMat)
                    if prereqMat(child, node) > 0 && relevant(child) == 0 && ~ismember(child, existing)
                        relevant(child) = 1;
                        queue(length(queue) + 1) = child;
                    end
                end
            end
            relevantInds = find(relevant > 0);
        end
        function prereqMat = getPrereqMatFromTable(obj, prereqTbl)
            %{
            Extracts the prerequistie matrix from a prerequisite table
            prereqTbl; table where the first column is course titles, and
            2nd-end columns are a square prerequisite matrix
            %}
            prereqMat = table2array(prereqTbl(:, 2 : end));
        end
        function constrainObjectiveAuxiliary(obj)
            %{
            Builds constraints representing the auxiliary objective.
            %}

            % Foreach semester, force the auxiliary variable to be greater
            % than the total stress from that semester
            for sInd = 1 : obj.numSems
                cons = zeros(1, obj.numVars);
                for cInd =  1 : obj.numCourses
                    cons(cInd + (sInd - 1) * obj.numCourses) = obj.getStress(cInd) * obj.semStressMultiplier(sInd);
                end
                cons(end) = -1;
                obj.ineqC = vertcat(obj.ineqC, cons);
                obj.ineqB = vertcat(obj.ineqB, 0);
            end
        end
        function constrainCompletion(obj)
            %{
            Constrain course completion. Required courses must be completed
            exactly once across the semesters. Prerequisite courses that
            are not in required must be completed at most once across the
            semesters.
            %}
            % Foreach course, constrain its completion
            for cInd = 1 : obj.numCourses
                cons = zeros(1, obj.numVars);
                for sInd = 1 : obj.numSems
                    cons(cInd + (sInd - 1) * obj.numCourses) = 1;
                end
                % Assign constraint as equality or inequality based on
                % whether it is required
                if (ismember(obj.smallPrereqTbl.Title(cInd), obj.required))
                    obj.eqC = vertcat(obj.eqC, cons);
                    obj.eqB = vertcat(obj.eqB, 1);
                else
                    obj.ineqC = vertcat(obj.ineqC, cons);
                    obj.ineqB = vertcat(obj.ineqB, 1);
                end
            end
        end
        function constrainSeason(obj)
            %{
            Constrain seasonal course availability. Non-fall courses have
            an zero-upper-bounded decision variable value for fall
            semesters. Similarly constrain for non-spring courses.
            %}
            % Foreach course, constrain its seasonal availability
            for cInd =  1 : obj.numCourses
                [isFall, isSpring] = obj.getSeasonal(cInd);
                if ~isFall
                    for sInd = obj.fallSems
                        obj.ub(cInd + (sInd - 1) * obj.numCourses) = 0;
                    end
                end
                if ~isSpring
                    for sInd = obj.springSems
                        obj.ub(cInd + (sInd - 1) * obj.numCourses) = 0;
                    end
                end
            end
        end
        function constrainPrereq(obj, cInd, prereqFlag, isStrict, isAnd)
            %{
            Constrain each course such that enrollment depends on
            satisfaction of prerequisites.
            IN
                cInd, obj.smallPrereqTbl-index of the course to constrain
                against its prereqs
                prereqFlag; flag in obj.prereqMat to target (distinguishes
                between strict/concurrent and/or prereqs)
                isStrict; boolean whether to target strict/concurrent
                prereqs
                isAnd; boolean whether to target and/or prereqs
            %}
            % Records the courses that prereq this course (cInd).
            % Iterate through each course, recording the indices of courses
            % that prereq this course.
            numPrereqs = 0;
            prereqInds = [];
            for pInd =  1 : obj.numCourses
                if obj.prereqMat(pInd, cInd) == prereqFlag % if the prereq-candidate has the prereqFlag, record its prereq status
                    numPrereqs = numPrereqs + 1;
                    prereqInds = vertcat(prereqInds, pInd);
                end
            end
            % if at least one prereq exists, constrain this course's (cInd)
            % decision variables such that this course cannot be enrolled
            % until prereqs are satisfied
            if numPrereqs > 0
                for thisSem = 1 : obj.numSems
                    % if prereq is strict, prereqs must be satisfied in
                    % previous semseter. else; concurrent prereqs may be
                    % satisfied in the same semester
                    if isStrict
                        lastSem = thisSem - 1;
                    else
                        lastSem = thisSem;
                    end
                    cons = zeros(1, obj.numVars);
                    % if prereq is and, all prereqs must be satisfied.
                    % else; at least one or prereq must be satisfied
                    if isAnd
                        cons(cInd + (thisSem - 1) * obj.numCourses) = numPrereqs;
                    else
                        cons(cInd + (thisSem - 1) * obj.numCourses) = 1;
                    end
                    % Foreach prereq, annotate its completion in an
                    % earlier/concurrent semester
                    for ind = 1 : length(prereqInds)
                        pInd = prereqInds(ind);
                        for prevSem = 1 : lastSem
                            cons(pInd + (prevSem - 1) * obj.numCourses) = -1;
                        end
                    end

                    % Append the new constraint to the class properties
                    obj.ineqC = vertcat(obj.ineqC, cons);
                    obj.ineqB = vertcat(obj.ineqB, 0);
                end
            end
        end
        function buildConstraints(obj)
            %{
            Builds all constraints
            %}
            % Initialize constraint containers
            obj.ineqC = [];
            obj.ineqB = [];
            obj.eqC = [];
            obj.eqB = [];
            obj.lb = zeros(obj.numVars, 1);
            obj.ub = ones(obj.numVars, 1);
            obj.ub(end) = Inf;

            % Build prerequisite constraints, iterating through each
            % course, each and/or state, and each strict/concurrents state
            obj.constrainObjectiveAuxiliary();
            obj.constrainCompletion();
            obj.constrainSeason();
            for cInd =  1 : obj.numCourses
                for isStrict = 0 : 1
                    for isAnd =  0 : 1
                        if isStrict
                            if isAnd
                                prereqFlag = obj.sAndFlag;
                            else
                                prereqFlag = obj.sOrFlag;
                            end
                        else
                            if isAnd
                                prereqFlag = obj.cAndFlag;
                            else
                                prereqFlag = obj.cOrFlag;
                            end
                        end
                        obj.constrainPrereq(cInd, prereqFlag, isStrict, isAnd);
                    end
                end
            end
        end
        function [sol, fval, exitflag, output] = solve(obj, maxNodes)
            %{
            Solves the MIP.
            OUT
                sol; decision variable optimal solution vector
                fval; optimal objective value (max stress across the
                semesters)
                exitflag; exitflag of intlinprog
                output; output return of intlinprog
            %}
            objective = zeros(1, obj.numVars);
            objective(end) = 1;
            intcon = 1 : (obj.numVars - 1);
            options = optimoptions('intlinprog', 'MaxNodes', maxNodes);
            [sol, fval, exitflag, output] = intlinprog(objective, intcon, obj.ineqC, obj.ineqB, obj.eqC, obj.eqB, obj.lb, obj.ub, [], options);
        end
        function tbl = solution2table(obj, sol, showAuxl)
            %{
            Converts a solution vector into a table for convenient
            visualization.
            IN
                sol; a vector of decision variable values (as output by
                obj.solve())
                showAuxl; boolean of whether to show auxiliary courses in
                the visualization table
            %}

            % Check if a solution exists.
            if isempty(sol)
                error("No feasible solution.");
            end

            % Foreach semester, record all courses taken that semester.
            tbl = table();
            maxCourses = 20;
            maxCounter = -1;
            for sInd =  1 : obj.numSems
                schedule = strings(maxCourses, 1); % stores the course titles this semester
                hours = strings(maxCourses, 1); % stores the credit hours of courses taken this semester
                stress = strings(maxCourses, 1); % stores the stress value of courses taken this semester
                courseCounter = 1;
                sumHours = 0;
                sumStress = 0;
                % Foreach course check for completion this semester
                for cInd =  1 : obj.numCourses
                    if sol(cInd + (sInd - 1) * obj.numCourses) > 0.9
                        cTitle = obj.ind2title(cInd, obj.smallPrereqTbl);
                        if showAuxl || extractBetween(cTitle, 1, 4) ~= "AUXL"
                            % Record properties of the course
                            courseCounter = courseCounter + 1;
                            if ismember(cTitle, obj.required)
                                schedule(courseCounter) = cTitle;
                            else
                                schedule(courseCounter) = strcat(cTitle,"*");
                            end
                            cHours = obj.getHours(cInd);
                            cStress = obj.getStress(cInd);
                            hours(courseCounter) = num2str(cHours);
                            stress(courseCounter) = num2str(cStress);
                            sumHours = sumHours + cHours;
                            sumStress = sumStress + cStress;
                        end
                    end
                end
                % Record the highest number of courses taken across all
                % semesters. Used for formatting the height of tbl.
                if maxCounter < courseCounter
                    maxCounter = courseCounter;
                end
                % Record summary/total information
                schedule(1) = "Totals:";
                hours(1) = num2str(sumHours);
                stress(1) = num2str(sumStress);
                % Append this semester's datatable to the overall table
                sTbl = table(schedule, hours, stress, 'VariableNames', ["Title", "Credit Hours", "Stress"]);
                tbl = horzcat(tbl, table(sTbl, 'VariableNames', strcat("Semester #", num2str(sInd))));
            end
            % Delete all empty spaces as counted by maxCounter
            tbl(maxCounter + 1 : end, :) = [];
        end
    end
end