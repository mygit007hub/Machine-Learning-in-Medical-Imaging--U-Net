function Y = vl_nnloss(X,c,dzdy,varargin)
%VL_NNLOSS CNN categorical or attribute loss.
%   Y = VL_NNLOSS(X, C) computes the loss incurred by the prediction
%   scores X given the categorical labels C.
%
%   The prediction scores X are organised as a field of prediction
%   vectors, represented by a H x W x D x N array. The first two
%   dimensions, H and W, are spatial and give the height and width of
%   the field;the third dimension D is the number of categories;
%   finally, the dimension N is the number of data items (images)
%   packed in the array. While often one has H = W = 1, W, H > 1 is
%   useful in dense labelling problems such as image segmentation.
%
%   The array C contains the categorical labels. In the simplest case,
%   C is an array of integers in the range [1, D] with an overall
%   number of elements equal to N. In this case, C is interpreted as
%   specifying one label per image. If H, W > 1, the same label is
%   implicitly applied to all spatial locations.
%
%   In the second form, C has dimension H x W x 1 x N and specifies a
%   categorical label for each spatial location.
%
%   In the third form, C has dimension H x W x D x N and specifies
%   attributes rather than categories. Here elements in C are either
%   +1 or -1 and C, where +1 denotes that an attribute is presnet and
%   -1 that it is not. The key difference is that multiple attributes
%   can be active at the same time, while categories are mutually
%   exclusive.
%
%   DZDX = VL_NNLOSS(X, C, DZDY) computes the derivative of the block
%   projected onto the output derivative DZDY. DZDX and DZDY have the
%   same dimensions as X and Y respectively.
%
%   VL_NNLOSS() supports several loss functions, which caxn be selected
%   by using the option `type` described below. When each scalar c in
%   C is interpreted as a categorical label (first two forms above),
%   the following losses can be used:
%
%   Classification error:: `classerror`
%     L(X,c) = (argmax_q X(q) ~= c). Note that the classification
%     error derivative is flat; therefore this loss is useful for
%     assesment, but not for training a model.
%
%   Log loss:: `log`
%     L(X,c) = - log(X(c)). This function assumes that X(c) is the
%     predicted probability of class c (hence the vector X must be non
%     negative and sum to one).
%
%   Softmax log loss (multinomial logistic loss):: `softmaxlog`
%     L(X,c) = - log(P(c)) where P(c) = exp(X(c)) / sum_q exp(X(q)).
%     This is the same as the `log` loss, but renormalizes the
%     predictions using the softmax function.
%
%   Multiclass hinge loss:: `mhinge`
%     L(X,c) = max{0, 1 - X(c)}. This function assumes that X(c) is
%     the score margin for class c against the other classes.  See
%     also the `mmhinge` loss below.
%
%   Multiclass structured hinge loss:: `mshinge`
%     L(X,c) = max{0, 1 - M(c)} where M(c) = X(c) - max_{q ~= c}
%     X(q). This is the same as the `mhinge` loss, but computes the
%     margin between the prediction scores first. This is also known
%     the Crammer-Singer loss, an example of a structured prediction
%     loss.
%
%   When C is a vector of binary attribures c in (+1,-1), each scalar
%   prediction score x is interpreted as voting for the presence or
%   absence of a particular attribute. The following losses can be
%   used:
%
%   Binary classification error:: `binaryerror`
%     L(x,c) = (sign(x - t) ~= c). t is a threshold that can be
%     specified using the `threshold` option and defaults to zero. If
%     x is a probability, it should be set to 0.5.
%
%   Binary log loss:: `binarylog`
%     L(x,c) = - log(c(x-0.5) + 0.5). x is assumed to be the
%     probability that the attribute is active (c=+1). Hence x must be
%     a number in the range [0,1]. This is the binary version of the
%     `log` loss.
%
%   Logistic log loss:: `logisticlog`
%     L(x,c) = log(1 + exp(- cx)). This is the same as the `binarylog`
%     loss, but implicitly normalizes the score x into a probability
%     using the logistic (sigmoid) function: p = sigmoid(x) = 1 / (1 +
%     exp(-x)). This is also equivalent to `softmaxlog` loss where
%     class c=+1 is assigned score x and class c=-1 is assigned score
%     0.
%
%   Hinge loss:: `hinge`
%     L(x,c) = max{0, 1 - cx}. This is the standard hinge loss for
%     binary classification. This is equivalent to the `mshinge` loss
%     if class c=+1 is assigned score x and class c=-1 is assigned
%     score 0.

% Copyright (C) 2014-15 Andrea Vedaldi.
% All rights reserved.
%
% This file is part of the VLFeat library and is made available under
% the terms of the BSD license (see the COPYING file).

opts.instanceWeights = [] ;
opts.classWeights = [] ;
opts.threshold = 0 ;
opts.operation = [];
opts.loss = 'softmaxlog' ;
opts = vl_argparse(opts,varargin) ;

inputSize = [size(X,1) size(X,2) size(X,3) size(X,4)] ;

% Form 1: C has one label per image. In this case, get C in form 2 or
% form 3.
c = gather(c) ;
if numel(c) == inputSize(4)
  c = reshape(c, [1 1 1 inputSize(4)]) ;
  c = repmat(c, inputSize(1:2)) ;
end

% --------------------------------------------------------------------
% Spatial weighting
% --------------------------------------------------------------------

labelSize = [size(c,1) size(c,2) size(c,3) size(c,4)] ;
assert(isequal(labelSize(1:2), inputSize(1:2))) ;
assert(labelSize(4) == inputSize(4)) ;
switch lower(opts.loss)
  case {'classerror', 'log', 'softmaxlog', 'mhinge', 'mshinge'}
    binary = false ;

    % there must be one categorical label per prediction vector
    assert(labelSize(3) == 1) ;

    % null labels denote instances that should be skipped
    instanceWeights = single(c(:,:,1,:) ~= 0) ;

  case {'binaryerror', 'binarylog', 'logistic', 'hinge'}
    binary = true ;

    % there must be one categorical label per prediction scalar
    assert(labelSize(3) == inputSize(3)) ;

    % null labels denote instances that should be skipped
    instanceWeights = single(c ~= 0) ;

  case {'regloss', 'relative', 'tukey', 'dotprod', 'rmse', 'absrel'}
    % regression using uniform weights
    instanceWeights = single( prod(labelSize(1:3)) * ones(inputSize(4),1) );
        
  otherwise
    error('Unknown loss ''%s''.', opts.loss) ;
end

if ~isempty(opts.instanceWeights)
  instanceWeights = bsxfun(@times, instanceWeights, opts.instanceWeights) ;
else
  instanceWeights = instanceWeights * (1 / prod(labelSize(1:3))) ;
end

% --------------------------------------------------------------------
% Do the work
% --------------------------------------------------------------------

switch lower(opts.loss)
  case {'log', 'softmaxlog', 'mhinge', 'mshinge'}
    % from category labels to indexes
    numPixelsPerImage = prod(inputSize(1:2)) ;
    numPixels = numPixelsPerImage * inputSize(4) ;
    imageVolume = numPixelsPerImage * inputSize(3) ;

    n = reshape(0:numPixels-1,labelSize) ;
    offset = 1 + mod(n, numPixelsPerImage) + ...
             imageVolume * fix(n / numPixelsPerImage) ;
    ci = offset + numPixelsPerImage * max(c - 1,0) ;
end

% ---------------------------------
% Forward                     
% ---------------------------------
if nargin <= 2 || isempty(dzdy)
  switch lower(opts.loss)
    case 'classerror'
      [~,chat] = max(X,[],3) ;
      t = single(c ~= chat) ;
    case 'log'
      t = - log(X(ci)) ;
    case 'softmaxlog'
      Xmax = max(X,[],3) ;
      ex = exp(bsxfun(@minus, X, Xmax)) ;
      t = Xmax + log(sum(ex,3)) - X(ci) ;
    case 'mhinge'
      t = max(0, 1 - X(ci)) ;
    case 'mshinge'
      Q = X ;
      Q(ci) = -inf ;
      t = max(0, 1 - X(ci) + max(Q,[],3)) ;
    case 'binaryerror'
      t = single(sign(X - opts.threshold) ~= c) ;
    case 'binarylog'
      t = -log(c.*(X-0.5) + 0.5) ;
    case 'logistic'
      %t = log(1 + exp(-c.*X)) ;
      a = -c.*X ;
      b = max(0, a) ;
      t = b + log(exp(-b) + exp(a-b)) ;
    case 'hinge'
      t = max(0, 1 - c.*X) ;
    case 'regloss'
      %t = vl_nnberhu(X,c); 
      t = vl_nnregloss(X, c);   %result is of size 1 x N
      %t = vl_nnhuberloss_grad(X,c);
      %t = vl_nnregloss(X, c, [], 'threshold', opts.threshold, 'operation', opts.operation);
      t = t' ;
    case 'tukey'
      t = vl_nntukeyloss(X,c,0,0,[]);
      instanceWeights = 1;
      %t = t';
    case 'dotprod'
      t = vl_nnelemwise(X,c);
      t = t';   %one loss per image in the batch
    case 'relative'
      X = reshape(X, inputSize(1)*inputSize(2)*inputSize(3), inputSize(4));
      c = reshape(c, size(X)) ; 
      %mask = isnan(c)|isinf(c);
      %mask = c > 0 ;
      diff = abs((X - c))./c ;    %absolute relative difference
      %diff(~mask) = 0;
      %n_pxls = sum(mask,1);
      n_pxls=12;
      t = sum(diff)./n_pxls ;    %sum over the mean error of every image  
      %t(n_pxls == 0) = 0;
    case 'absrel'
      t = vl_nnLoss_rel(X,c);
      t = t';
    case 'rmse'
      X = reshape(X, inputSize(1)*inputSize(2)*inputSize(3), inputSize(4));
      c = reshape(c, size(X)) ; 
      %X = X([1:3,7:9], :);
      %c = c([1:3,7:9], :);
      %mask = isnan(c)|isinf(c);
      %mask = c > 0;
      diff = (X-c).^2 ;    %absolute relative difference
      %diff(~mask) = 0;
      %n_pxls = sum(mask,1);
      n_pxls=6;
      t = (sum(diff)./n_pxls).^0.5 ;    %sum over the mean error of every image  
      %t(n_pxls==0)=0;
  end
  Y = instanceWeights(:)' * t(:) ;  %sum of losses in the batch (to be divided later on with the number of images)

% ---------------------------------
% Backwards
% ---------------------------------
else
  switch lower(opts.loss)
    case 'classerror'
      Y = zerosLike(X) ;
    case 'log'
      Y = zerosLike(X) ;
      Y(ci) = (- dzdy * instanceWeights) ./ max(X(ci), 1e-8) ;
    case 'softmaxlog'
      Xmax = max(X,[],3) ;
      ex = exp(bsxfun(@minus, X, Xmax)) ;
      Y = bsxfun(@rdivide, ex, sum(ex,3)) ;
      Y(ci) = Y(ci) - 1 ;
      Y = bsxfun(@times, dzdy * instanceWeights, Y) ;
    case 'mhinge'
      Y = zerosLike(X) ;
      Y(ci) = (- dzdy * instanceWeights) .* (X(ci) < 1) ;
    case 'mshinge'
      Q = X ;
      Q(ci) = -inf ;
      [~, q] = max(Q,[],3) ;
      qi = offset + numPixelsPerImage * (q - 1) ;
      W = (dzdy * instanceWeights) .* (X(ci) - X(qi) < 1) ;
      Y = zerosLike(X) ;
      Y(ci) = - W ;
      Y(qi) = + W ;
    case 'binaryerror'
      Y = zerosLike(X) ;
    case 'binarylog'
      Y = - (dzdy * instanceWeights) ./ (X + (c-1)*0.5) ;
    case 'logistic'
      % t = exp(-Y.*X) / (1 + exp(-Y.*X)) .* (-Y)
      % t = 1 / (1 + exp(Y.*X)) .* (-Y)
      Y = (- dzdy * instanceWeights) .* c ./ (1 + exp(c.*X)) ;
    case 'hinge'
      Y = (- dzdy * instanceWeights) .* c .* (c.*X < 1) ;
    case 'regloss'
      %Y = vl_nnberhu(X, c, dzdy); 
      Y = vl_nnregloss(X,c,dzdy);
      %Y = vl_nnhuberloss_grad(X, c, dzdy);
      %Y = vl_nnregloss(X, c, dzdy, 'threshold', opts.threshold, 'operation', opts.operation);
    case 'tukey'
      Y = vl_nntukeyloss(X,c,0,0,dzdy);
    case 'absrel'
      Y = vl_nnLoss_rel(X,c,dzdy);
      
    case 'dotprod'
      Y = vl_nnelemwise(X, c, dzdy);
  end
end


% --------------------------------------------------------------------
function y = zerosLike(x)
% --------------------------------------------------------------------
if isa(x,'gpuArray')
  y = gpuArray.zeros(size(x),'single') ;
else
  y = zeros(size(x),'single') ;
end


function ci = getIndex(c, inputSize)
