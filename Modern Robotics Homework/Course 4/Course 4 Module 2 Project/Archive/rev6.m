clear  
clc;  

%% Load Obstacles  
obstacles = readmatrix('obstacles.csv'); % Format: [x_center, y_center, radius]

%% Parameters and Workspace Setup  
x_limit = [-0.5, 0.5];  
y_limit = [-0.5, 0.5];  

start = [-0.5, -0.5];  
goal  = [0.5, 0.5];  

max_iterations = 5000;  
step_size = 0.05;  
goal_threshold = 0.05;  

rng('shuffle');  

%% Initialize the RRT Tree  
tree.nodes = [];  
tree.edges = [];  
tree.nodes(1,:) = [1, start, -1, 0]; % Added cost column  
node_count = 1;  
goal_reached = false;  
goal_node_id = -1;  

%% Improved Collision Checking Function  
function collision = check_collision(x1, y1, x2, y2, obstacles)
    collision = false;
    for i = 1:size(obstacles, 1)
        x_c = obstacles(i, 1);
        y_c = obstacles(i, 2);
        r = obstacles(i, 3);

        dx = x2 - x1;
        dy = y2 - y1;
        a = dx^2 + dy^2;
        b = 2 * (dx * (x1 - x_c) + dy * (y1 - y_c));
        c = (x1 - x_c)^2 + (y1 - y_c)^2 - r^2;

        discriminant = b^2 - 4*a*c;
        if discriminant >= 0  % Intersection exists
            t1 = (-b + sqrt(discriminant)) / (2 * a);
            t2 = (-b - sqrt(discriminant)) / (2 * a);

            if (t1 >= 0 && t1 <= 1) || (t2 >= 0 && t2 <= 1)
                collision = true;
                return;
            end
        end
    end
end  

%% Begin RRT Algorithm  
for iter = 1:max_iterations  
    if rand() < 0.1  
        x_rand = goal;  % Bias sampling towards the goal 10% of the time  
    else  
        x_rand = [rand() * diff(x_limit) + x_limit(1), rand() * diff(y_limit) + y_limit(1)];  
    end  

    distances = sqrt((tree.nodes(:,2) - x_rand(1)).^2 + (tree.nodes(:,3) - x_rand(2)).^2);  
    [~, idx] = min(distances);  
    nearest_node = tree.nodes(idx, 2:3);  
    parent_cost = tree.nodes(idx, 5); % Retrieve parent node's cost  

    theta = atan2(x_rand(2) - nearest_node(2), x_rand(1) - nearest_node(1));  
    new_x = nearest_node(1) + step_size * cos(theta);  
    new_y = nearest_node(2) + step_size * sin(theta);  

    if new_x < x_limit(1) || new_x > x_limit(2) || new_y < y_limit(1) || new_y > y_limit(2)  
        continue;  
    end  

    if check_collision(nearest_node(1), nearest_node(2), new_x, new_y, obstacles)
        continue; % Skip if in collision
    end

    edge_cost = sqrt((new_x - nearest_node(1))^2 + (new_y - nearest_node(2))^2);  
    cumulative_cost = parent_cost + edge_cost;  

    node_count = node_count + 1;  
    tree.nodes(node_count,:) = [node_count, new_x, new_y, tree.nodes(idx,1), cumulative_cost];  
    tree.edges(node_count - 1,:) = [node_count, tree.nodes(idx,1), edge_cost, cumulative_cost];  

    if sqrt((new_x - goal(1))^2 + (new_y - goal(2))^2) < goal_threshold  
        goal_reached = true;  
        goal_node_id = node_count;  
        fprintf('Goal reached at iteration %d\n', iter);  
        break;  
    end  
end  

%% Backtrack to Build the Final Path (Collision-Free)  
path_nodes = [];  
if goal_reached  
    current = goal_node_id;  
    while current ~= -1  
        parent_id = tree.nodes(current, 4);  

        if parent_id ~= -1 && check_collision(tree.nodes(parent_id, 2), tree.nodes(parent_id, 3), tree.nodes(current, 2), tree.nodes(current, 3), obstacles)  
            fprintf('Collision detected at node %d, skipping.\n', current);
            current = parent_id; % Move to previous node without adding to path
            continue;
        end  

        path_nodes = [current, path_nodes]; % Append node IDs
        current = tree.nodes(current, 4);  
    end  
else  
    fprintf('Goal not reached within maximum iterations.\n');  
end  

%% Save CSV Files in "results" Folder  
resultsFolder = 'results';  
if ~exist(resultsFolder, 'dir')  
    mkdir(resultsFolder);  
end  

writematrix(tree.nodes, fullfile(resultsFolder, 'nodes.csv'));  
writematrix(tree.edges, fullfile(resultsFolder, 'edges.csv'));  

if goal_reached  
    writematrix(path_nodes, fullfile(resultsFolder, 'path.csv')); % Path stored in a single row
end  

fprintf('Results saved in folder: %s\n', resultsFolder);