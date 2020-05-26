##
# Controller for Admin::EditableBlock. More details can be found there.
##

class Admin::EditableBlocksController < AdminController
  load_and_authorize_resource class: Admin::EditableBlock

  ##
  # GET /admin/editable_blocks
  #
  # GET /admin/editable_blocks.json
  ##
  def index
    @title = 'Editable Blocks'
    
    @editable_blocks = @editable_blocks.group_by(&:group)
    
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @editable_blocks }
    end
  end

  ##
  # GET /admin/editable_blocks/new
  #
  # GET /admin/editable_blocks/new.json
  ##
  def new
    # The title is set by the view.
    @editable_block.name = params[:name]

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @editable_block }
    end
  end

  ##
  # GET /admin/editable_blocks/1/edit
  ##
  def edit
    # The title is set by the view.
  end

  ##
  # POST /admin/editable_blocks
  #
  # POST /admin/editable_blocks.json
  ##
  def create
    respond_to do |format|
      if @editable_block.save
        format.html { redirect_to admin_editable_blocks_url, notice: 'Editable block was successfully created.' }
        format.json { render json: admin_editable_blocks_url, status: :created, location: @editable_block }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: admin_editable_blocks_url.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/editable_blocks/1
  #
  # PUT /admin/editable_blocks/1.json
  ##
  def update
    respond_to do |format|
      if @editable_block.update(editable_block_params)
        format.html { redirect_to admin_editable_blocks_url, notice: 'Editable block was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: admin_editable_blocks_url.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/editable_blocks/1
  #
  # DELETE /admin/editable_blocks/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@editable_block)

    respond_to do |format|
      format.html { redirect_to admin_editable_blocks_url }
      format.json { head :no_content }
    end
  end

  private

  def editable_block_params
    params.require(:admin_editable_block).permit(:content, :name, :admin_page, :group,
                                                 attachments_attributes: [:id, :_destroy, :name, :file])
  end
end
