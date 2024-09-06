classdef PrereqProcess < handle
    %{
    Encapsulates operations that parse prerequisite data.
    %}
    properties
        auxCounter  % Numerical portion of course code for AUXL auxiliary courses
        mat         % matrix representing prerequisites. element i,j  describes if course i is a prerequisite for course j
        courses     % list of course titles as strings
        prereqStrs  % list of prerequisite strings parallel to obj.courses
        coreqStrs   % list of corequisite strings parallel to obj.courses
        sAndInt     % flag in obj.mat representing a strict-and prereq
        sOrInt      % flag in obj.mat representing a strict-or prereq
        cAndInt     % flag in obj.mat representing a concurrent-and prereq
        cOrInt      % flag in obj.mat representing a concurrent-or prereq
    end
    methods
        function obj = PrereqProcess(courses, prereqStrs, coreqStrs)
            %{
            Constructor. Intializes class properties.
            IN
                courses; list of strings of course titles
                prereqStrs; list of strings representing each course's
                prereqs (parallel to courses)
                coreqStrs; list of strings representing each course's
                coreqs (parallel to courses)
            %}
            obj.courses = courses;
            obj.prereqStrs = prereqStrs;
            obj.coreqStrs = coreqStrs;
            obj.auxCounter = 100;
            obj.mat = zeros(length(courses));
            obj.sAndInt = 1;
            obj.sOrInt = 2;
            obj.cAndInt = 3;
            obj.cOrInt = 4;
            if length(courses) ~= length(prereqStrs)
                error("Number of prerequisite strings does not match number of course strings.")
            end
            if length(courses) ~= length(coreqStrs)
                error("Number of corequisite strings does not match the number of course strings.")
            end
        end
        function [lInd, rInd, expr] = findInternalExpr(obj, str)
            %{
            Locates an internal expression in str. Ie finds the innermost
            parentheses expression.
            IN
                str; a prerequiste string
            OUT
                lInd; integer index of the left parentheses (-1 if no
                parenthetical exists)
                rInd; integer index of the right parentheses (-1 if no
                parenthetical exists)
                expr; string located between these innermost parentheses
            %}
            % Find innermost left/right parentheses
            rInd = -1;
            lInd = -1;
            for ind = 1 : strlength(str)
                if extractBetween(str, ind, ind) == ")"
                    rInd = ind;
                    break
                end
            end
            for ind = rInd - 1 : -1 : 1
                if extractBetween(str, ind, ind) == "("
                    lInd = ind;
                    break
                end
            end
            % If an innermost parentheses exists, extract contents. If no
            % innermost parentheses exists, the entire input str is an
            % innermost expression.
            if lInd == -1
                expr = str;
            else
                expr = extractBetween(str, lInd + 1, rInd - 1);
            end
        end
        function [auxInd, auxTitle] = newVar(obj)
            %{
            Creates a new auxiliary course, growing obj.courses and obj.mat
            to account for this new course.
            %}
            % Grow the obj.mat prereq matrix by one size, representing the
            % new course.
            numVars = height(obj.mat);
            obj.mat = horzcat(obj.mat, zeros(numVars, 1));
            numVars = numVars + 1;
            obj.mat = vertcat(obj.mat, zeros(1, numVars));
            
            % Add new course to obj.course courselist, using arbitrary
            % "AUXL xxx" course code
            auxTitle = strcat("AUXL ", num2str(obj.auxCounter));
            obj.courses = vertcat(obj.courses, auxTitle);
            obj.auxCounter = obj.auxCounter + 1;
            auxInd = numVars;
        end
        function title = ind2title(obj, ind)
            %{
            Gets the title of the course at index ind in obj.courses
            %}
            title = obj.courses(ind);
        end
        function [ind, found] = title2ind(obj, title)
            %{
            Gets the index of the course with input title in obj.courses
            %}
            ind = find(obj.courses == title);
            found = true;
            if length(ind) ~= 1
                ind = -1;
                found = false;
            end
        end
        function parseCourseSet(obj, str, operatorStr, prereqInt, courseInd)
            %{
            Parses a prerequisite string that DOES NOT contain any
            parenthesized expressions. Ie, processes str strings of form
            "<COURSE> AND <COURSE> AND . . . " or "<COURSE> OR <COURSE> OR
            ..."
            Updates obj.mat to record the parsed prerequisite.
            IN
                str; prerequiste string to parse. Must have form specified
                above.
                operatorStr; either " OR " or " AND "
                prereqInt; the flag used to signal that the courses are
                requisites (see obj.sAndInt, obj.cOrInt, etc.)
                courseInd; integer index of the course whose prereqs should
                be parsed
            %}
            % if the course has no prereqs, then we have nothing to parse
            if strlength(str) == 0
                return
            end
            % if the course does not have the operatorStr, then the
            % prerequiste str must contain a singleton course.
            if ~contains(str, operatorStr)
                [prereqInd, found] = obj.title2ind(strip(str));
                if found
                    obj.mat(prereqInd, courseInd) = prereqInt;
                end
                return
            end

            % Case where the prereq str has multiple courses.
            prereqArr = strip(split(str, operatorStr)); % split into each prereq course title
            for ind = 1 : length(prereqArr)
                % if the course exists, then use int flags to record that
                % it is a prerequisite (sometimes a prereq course title
                % does not exist because the dataset is outdated).
                prereq = prereqArr(ind);
                [prereqInd, found] = obj.title2ind(prereq);
                if found
                    obj.mat(prereqInd, courseInd) = prereqInt;
                end
            end
        end
        function parseCorequisite(obj, courseInd1, courseInd2)
            %{
            Parses a corequisite. Updates obj.mat to record that the
            courses at input indices are concurrent-and prerequistes of each
            other
            In
                courseInd1/2; integer indices of the courses in obj.courses
                that are corequisites
            %}
            obj.mat(courseInd1, courseInd2) = obj.cAndInt;
            obj.mat(courseInd2, courseInd1) = obj.cAndInt;
        end
        function parsePrerequisite(obj, str, courseInd)
            %{
            Parses the entire prerequiste str of the specified course.
            While the input str contains a parenthetical, this function
            identifies the innermost parenthetical & replaces it with a
            single auxiliary course representing that parenthesized prereq.
            IN
                str; entire prerequisite string of course
                courseInd; integer index of the course in obj.courses whose
                prereqs should be parsed
            %}
            % Preprocess for homogeneity. Strip whitespace. Then add
            % parentheses on ends of str if there are unequal counts of
            % left/right parens.
            str = strip(str);
            while length(strfind(str, "(")) > length(strfind(str, ")"))
                str = strcat(str, ")");
            end
            while length(strfind(str, "(")) < length(strfind(str, ")"))
                str = strcat("(", str);
            end

            % While str contains a parenthesized prereq, create an
            % auxiliary course to represent that prereq, then replace the
            % entire parenthetical expression with the auxiliary course.
            while contains(str, "(")
                [auxInd, auxTitle] = newVar(obj); % create auxl course
                [lInd, rInd, expr] = obj.findInternalExpr(str); % find innermost parenthetical
                % Parse the innermost parenthetical as if it is a
                % concurrent prereq for the auxiliary course.
                if contains(expr, " OR ")
                    obj.parseCourseSet(expr, " OR ", obj.cOrInt, auxInd);
                else
                    obj.parseCourseSet(expr, " AND ", obj.cAndInt, auxInd);
                end
                % Replace parenthetical with auxiliary course
                str = strcat(extractBetween(str, 1, lInd - 1), auxTitle, extractBetween(str, rInd + 1, strlength(str)));
            end
            % Parse the str prereq now that it has been simplified to have
            % no parenthetical prereqs
            if contains(str, " OR ")
                obj.parseCourseSet(str, " OR ", obj.sOrInt, courseInd);
            else
                obj.parseCourseSet(str, " AND ", obj.sAndInt, courseInd);
            end
        end
        function buildPrereqMatrix(obj)
            %{
            Construts obj.mat to represent requisites. The integer flag at 
            element i, j represents how course i is a prerequisite of
            course j.
            %}
            % Parse all prerequisites
            numRealCourses = length(obj.courses);
            for ind = 1 : numRealCourses
                obj.parsePrerequisite(obj.prereqStrs(ind), ind);
            end
            % Parse all corequisites
            for ind = 1 : numRealCourses
                coreqTitle = obj.coreqStrs(ind);
                if strlength(coreqTitle) > 0
                    [coreqInd, found] = obj.title2ind(coreqTitle);
                    if found
                        obj.parseCorequisite(coreqInd, ind);
                    end
                end
            end
        end
        function mat = getPrereqMatrix(obj)
            mat = obj.mat;
        end
        function titles = getTitles(obj)
            titles = obj.courses;
        end
        function writePrereqMatrixXlsx(obj, filename)
            %{
            Writes the obj.mat prereq matrix to xlsx file at specified
            filename.
            %}
            titles = table(obj.courses, 'VariableNames', "Title");
            tbl = cell2table(num2cell(obj.mat), 'VariableNames', obj.courses);
            tbl = horzcat(titles, tbl);
            writetable(tbl, filename);
        end
    end
end