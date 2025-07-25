function isStable = checkAssemblyStability(bodies, contacts, mu)
% CHECKASSEMBLYSTABILITY Determines whether a planar assembly is stable.
%
% This function checks if a planar assembly of rigid bodies, connected by
% frictional contacts and subjected to gravity, can maintain static equilibrium.
% It formulates the problem as a linear program (LP) to find if a feasible
% set of contact forces exists.
%
% INPUTS:
%   bodies   - Struct array with fields:
%              .mass  (scalar) - Mass of the body (kg)
%              .com   (2x1 position) - Center of mass [x; y] in world frame (m)
%   contacts - Struct array with fields:
%              .body1     (integer) - Index of body 1 (or 0 for ground)
%              .body2     (integer) - Index of body 2 (or 0 for ground)
%              .normal    (2x1 unit normal) - Unit vector pointing INTO body1 (m)
%              .position  (2x1 position) - Contact position in world frame [x; y] (m)
%   mu       - Vector of per-contact friction coefficients (length = # contacts)
%
% OUTPUT:
%   isStable - logical (true if equilibrium is possible, false if assembly collapses)

% ------------------ Input Validation ------------------
m = length(bodies);   % Number of bodies
n = length(contacts); % Number of contacts

if length(mu) ~= n
    error('Input Error: Length of mu (%d) must match number of contacts (%d).', length(mu), n);
end

% Validate that all body indices are within bounds (1 to m for bodies, 0 for ground)
allBodies = [ [contacts.body1], [contacts.body2] ];
allBodies = allBodies(allBodies > 0); % Exclude ground (0) from max check
if ~isempty(allBodies) % Check only if there are actual bodies referenced
    maxBodyIdx = max(allBodies);
    if maxBodyIdx > m
        error('Input Error: Contact refers to body index %d, but only %d bodies are defined.', maxBodyIdx, m);
    end
end

% ------------------ Assembly of Linear Program Matrices ------------------

% A * x = b, where x are the force magnitudes along friction cone edges
% There are 3 equilibrium equations (Fx, Fy, Mz) for each of 'm' bodies.
% Each of 'n' contacts contributes 2 force components (from 2 friction cone edges).
A = zeros(3 * m, 2 * n); % Wrench matrix (coefficients for unknown contact forces)
b = zeros(3 * m, 1);     % External wrench vector (from gravity)
g = 9.81;                % Acceleration due to gravity (m/s^2)

% --- Populate A matrix (Wrench Matrix) ---
% Each column in A corresponds to a force generated by one of the friction cone edges.
% The unknowns (x) in linprog will be the non-negative multipliers of these edge forces.
for j = 1:n % Iterate through each contact
    c = contacts(j);
    mu_j = mu(j); % Friction coefficient for this contact

    % Calculate tangent vector (90 degrees CCW from normal)
    t = [-c.normal(2); c.normal(1)]; 

    % Calculate the two unit vectors representing the edges of the friction cone
    % f1_dir: normal + mu*tangent (one edge direction)
    % f2_dir: normal - mu*tangent (other edge direction)
    f1_dir = (c.normal + mu_j * t);
    f2_dir = (c.normal - mu_j * t);
    
    % Normalize force directions to unit vectors
    % Check for near-zero norm to prevent division by zero, though unlikely with unit normals
    if norm(f1_dir) > 1e-9
        f1_dir = f1_dir / norm(f1_dir);
    else
        f1_dir = [0;0]; 
    end
    if norm(f2_dir) > 1e-9
        f2_dir = f2_dir / norm(f2_dir);
    else
        f2_dir = [0;0]; 
    end

    pos = c.position; % Contact position in world frame

    % Iterate through the two friction cone edge directions (f1_dir, f2_dir)
    for i = 1:2
        f = (i == 1) * f1_dir + (i == 2) * f2_dir; % Current edge direction vector
        
        % Calculate column index in A for this specific force edge
        % Columns are grouped by contact: [contact1_f1, contact1_f2, contact2_f1, contact2_f2, ...]
        col_idx = 2*(j-1) + i;

        % Apply force to body1 (+f) and body2 (-f)
        % For ground contacts (body1 or body2 is 0), force is only applied to the non-ground body.
        
        % Contribution to body1's equilibrium equations
        if c.body1 ~= 0 % If body1 is not ground
            bidx1 = c.body1; % Index of body1
            row_start1 = 3*(bidx1-1); % Starting row for body1's equations

            r1 = pos - bodies(bidx1).com; % Vector from body1's COM to contact point

            % Add force components to body1's rows (Fx, Fy)
            A(row_start1+1:row_start1+2, col_idx) = A(row_start1+1:row_start1+2, col_idx) + f;
            
            % Add moment component to body1's row (Mz)
            % Moment = r x f (2D cross product: rx*fy - ry*fx)
            A(row_start1+3, col_idx) = A(row_start1+3, col_idx) + (r1(1)*f(2) - r1(2)*f(1));
        end

        % Contribution to body2's equilibrium equations
        if c.body2 ~= 0 % If body2 is not ground
            bidx2 = c.body2; % Index of body2
            row_start2 = 3*(bidx2-1); % Starting row for body2's equations

            r2 = pos - bodies(bidx2).com; % Vector from body2's COM to contact point

            % Add negative force components to body2's rows (Fx, Fy)
            % Body 2 experiences -f (reaction force) from Body 1
            A(row_start2+1:row_start2+2, col_idx) = A(row_start2+1:row_start2+2, col_idx) - f;
            
            % Add negative moment component to body2's row (Mz)
            A(row_start2+3, col_idx) = A(row_start2+3, col_idx) - (r2(1)*f(2) - r2(2)*f(1));
        end
    end
end

% --- Populate b vector (External Wrench from Gravity) ---
% Gravity acts only in the Y-direction (downwards) at the center of mass.
% In A*x=b, b represents the NEGATIVE of the external forces applied by gravity.
% For example, if gravity is -m*g in Y, then b should be +m*g in Y to balance it.
for i = 1:m % Iterate through each body
    row_start = 3*(i-1); % Starting row for body i's equations
    % b(row_start+1) is Fx = 0 (no external x-force due to gravity)
    % CORRECTED LINE: b should be positive to balance negative gravity force
    b(row_start+2) = bodies(i).mass * g; % Fy = +mass * g (to balance -mass*g from gravity)
    % b(row_start+3) is Mz = 0 (no external moment from gravity about COM)
end

% ------------------ Solve Linear Program ------------------
% We are looking for a feasible solution (existence of x) that satisfies A*x = b
% and x >= 0 (since x represents non-negative force magnitudes).
% An arbitrary objective function (f = zeros) is used for feasibility checking.
f_obj = zeros(2 * n, 1);     % Objective function coefficients (don't care about min/max)
lb = zeros(2 * n, 1);        % Lower bounds for force magnitudes (must be non-negative)

% Configure linprog options for detailed debugging
options = optimoptions('linprog', ...
    'Display', 'iter', ...             % Show iteration progress (valid option)
    'Diagnostics', 'on', ...           % Provide detailed problem setup diagnostics
    'Algorithm', 'interior-point', ... % Explicitly use interior-point algorithm
    'ConstraintTolerance', 1e-8, ...   % Tighten constraint tolerance
    'OptimalityTolerance', 1e-8);      % Tighten optimality tolerance

% --- FOR DEBUGGING ONLY: Save A, b, and lb to base workspace for external inspection ---
assignin('base', 'A_lp_debug', A);
assignin('base', 'b_lp_debug', b);
assignin('base', 'lb_lp_debug', lb);
% --- END DEBUGGING CODE ---

try
    [~, ~, exitflag, output_struct] = linprog(f_obj, [], [], A, b, lb, [], options);
catch ME
    % Catch potential errors from linprog itself (e.g., license issues, setup problems).
    warning('Linear programming (linprog) failed: %s', ME.message);
    exitflag = -99; % Custom error code for linprog failure
    output_struct.message = ME.message; % Store error message in output struct
end

% ------------------ Determine Stability ------------------
% If exitflag is 1, linprog found a feasible solution, meaning equilibrium is possible.
isStable = (exitflag == 1);

end